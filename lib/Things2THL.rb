# -*- coding: utf-8 -*-

#require File.join(File.dirname(__FILE__), *%w".. .. things-rb lib things")
require "ostruct"
require 'time'
begin; require 'rubygems'; rescue LoadError; end
require 'appscript'; include Appscript
require 'hpricot'

######################################################################

module Things2THL
  module Version
    MAJOR  = 0
    MINOR  = 7
    PATCH  = 0

    STRING = [MAJOR, MINOR, PATCH].join(".")
  end

  ####################################################################

  module Constants
    # Ways in which the items can be structured on the THL side.
    # Elements are: <Things item> => [<THL item>, {prop mapping}, postblock],
    # where {prop mapping} is a map containing <Things prop> => <THL prop>.
    # <Things prop> is a symbol representing the name of a Node property.
    # <THL prop> can be any of the following
    #     :symbol   => value of <Things prop> is assigned to this prop
    #     [:symbol, {hash}] => value of <Things prop> is looked up in {hash}
    #                          and the corresponding value is assigned to :symbol
    #     {value1 => :symbol1, value2 => :symbol2} => if value of <Things prop>
    #                 is value1, then :symbol1 prop in THL is set to true, etc.
    # postblock, if given, should be a code block that will receive
    #    the original node, the produced new properties hash and the
    #    Things2THL object as parameters, and do any necessary
    #    postprocessing on the new properties
    #    If postblock inserts in the properties hash an item with the key
    #    :__newnodes__, it should be an array with items of the form
    #       { :new => :what,
    #         :with_properties => { properties }
    #       }
    #    Those items will be added to the new THL node immediately
    #    after its creation.
    STRUCTURES = {
      :projects_as_lists => { 
        :area => [:folder,
                  {
                    :name => :name,
                  }],
        :project => [:list,
                     {
                       :name => :name,
                       :creation_date => :created_date,
                     },
                     Proc.new {|node,prop,obj|
                       obj.add_list_notes(node,prop)
                       obj.add_project_duedate(node,prop)
                     }
                    ],
        :selected_to_do => [:task,
                            {
                              :name => :title,
                              :creation_date => :created_date,
                              :due_date => :due_date,
                              :completion_date => :completed_date,
                              :cancellation_date => :canceled_date,
                              :activation_date => :start_date,
                              :status => {
                                :completed => :completed,
                                :canceled  => :canceled,
                              },
                            },
                            Proc.new {|node,prop,obj|
                              obj.add_notes(node,prop)
                              obj.fix_completed_canceled(node, prop)
                              obj.archive_completed(prop)
                              obj.process_tags(node, prop, true, true)
                              obj.check_today(node, prop)
                            }
                           ]
      },
      :projects_as_tasks => {
        :area => [:list,
                  {
                    :name => :name,
                  }],
        :project => [:task,
                     {
                       :name => :title,
                       :creation_date => :created_date,
                       :due_date => :due_date,
                       :completion_date => :completed_date,
                       :cancellation_date => :canceled_date,
                       :activation_date => :start_date,
                       :status => {
                         :completed => :completed,
                         :canceled  => :canceled,
                       },
                     },
                     Proc.new {|node,prop,obj|
                       obj.add_notes(node,prop)
                       obj.fix_completed_canceled(node, prop)
                       obj.archive_completed(prop)
                       obj.process_tags(node, prop, false, true)
                     }
                    ],
        :selected_to_do => [:task,
                            {
                              :name => :title,
                              :creation_date => :created_date,
                              :due_date => :due_date,
                              :completion_date => :completed_date,
                              :cancellation_date => :canceled_date,
                              :activation_date => :start_date,
                              :status => {
                                :completed => :completed,
                                :canceled  => :canceled,
                              },
                            },
                            Proc.new {|node,prop,obj|
                              obj.add_notes(node,prop)
                              obj.fix_completed_canceled(node, prop)
                              obj.archive_completed(prop)
                              obj.process_tags(node, prop, false, true)
                              obj.check_today(node, prop)
                            }
                           ]
      },
      :projects_areas_as_lists => {
        :area => [:list,
                  {
                    :name => :name,
                  }],
        :project => [:list,
                     {
                       :name => :name,
                       :creation_date => :created_date,
                     },
                     Proc.new {|node,prop,obj|
                       obj.add_list_notes(node,prop)
                       obj.add_project_duedate(node,prop)
                     }
                    ],
        :selected_to_do => [:task,
                            {
                              :name => :title,
                              :creation_date => :created_date,
                              :due_date => :due_date,
                              :completion_date => :completed_date,
                              :cancellation_date => :canceled_date,
                              :activation_date => :start_date,
                              :status => {
                                :completed => :completed,
                                :canceled  => :canceled,
                              },
                            },
                            Proc.new {|node,prop,obj|
                              obj.add_notes(node,prop)
                              obj.fix_completed_canceled(node, prop)
                              obj.archive_completed(prop)
                              obj.process_tags(node, prop, true, true)
                              obj.check_today(node, prop)
                            }
                           ]
      }
    }

    # For some reason some entities in THL use "title", others use "name"
    TITLEPROP = {
      :folder => :name,
      :list => :name,
      :task => :title
    }

    # Time units for time-estimate tags
    TIMEUNITS = {
      "sec" => 1,
      "min" => 60,
      "hr"  => 60*60,
      "hour" => 60*60,
    }

  end ### module Constants

  ####################################################################

  # Wrapper around an AS Things node to provide easier access to its props
  # For each property 'prop' of the node, it defines two methods:
  # prop() returns the value, converting :missing_value to nil
  # prop?() returns true/false to indicate if the value is set and is not :missing_value
  # Not all the AS properties respond properly to get(), so not all of the
  # auto-defined methods will work properly.
  class ThingsNode
    attr_accessor :node

    @@defined={}

    def initialize(node)
      @node = node
      @values = {}
      return unless @@defined.empty?
      (node.properties + node.elements).each do |prop|
        next if @@defined.has_key?(prop)
        puts "Defining ThingsNode.#{prop}" if $DEBUG
        @@defined[prop]=true
        case prop
        # For area, project and some others, convert the result to a ThingsNode as well
        when 'area', 'project', 'areas', 'projects', 'parent_tag', 'delegate'
          ThingsNode.class_eval <<-EOF
          def #{prop}
            return @values['#{prop}'] if @values.has_key?('#{prop}')
            value=node.#{prop}.get
              @values['#{prop}']=case value
                                 when nil, :missing_value
                                   nil
                                 else
                                   ThingsNode.new(value)
                                 end
          end
          def #{prop}?
            !!#{prop}
          end
          EOF
        when 'to_dos', 'tags'
          # For to_dos and tags, map the returned array to ThingsNode as well
          ThingsNode.class_eval <<-EOF
          def #{prop}
            return @values['#{prop}'] if @values.has_key?('#{prop}')
            value=node.#{prop}.get
              @values['#{prop}']=case value
                                 when nil, :missing_value
                                   nil
                                 else
                                   value.map { |n| ThingsNode.new(n) }
                                 end
          end
          def #{prop}?
            !!#{prop}
          end
          EOF
        else
          ThingsNode.class_eval <<-EOF
          def #{prop}
            return @values['#{prop}'] if @values.has_key?('#{prop}')
            value=node.#{prop}.get
            value=nil if value==:missing_value
            @values['#{prop}']=value
          end
          def #{prop}?
            !!#{prop}
          end
          EOF
          # Some smarts for specific attributes
          if prop == 'class_'
            ThingsNode.class_eval 'alias_method :type, :class_'
          end
        end
      end
    end
  end ### ThingsNode

  ####################################################################

  class Converter
    attr_accessor :options, :things, :thl

    def initialize(opt_struct = nil, things_location = nil, thl_location = nil)
      @options=opt_struct || Things2THL.default_options
      thingsappname=things_location || 'Things'
      thlappname=thl_location || 'The Hit List'
      begin
        @things = Appscript.app(thingsappname)
        @thl = Appscript.app(thlappname)
      rescue ApplicationNotFoundError => e
        puts "I could not open one of the needed applications: #{e.message}"
        exit(1)
      end

      # Regular expression to match context tags. Compile it here to avoid
      # repetition later on.
      options.contexttagsregex_compiled = Regexp.compile(options.contexttagsregex) if options.contexttagsregex
      # Regular expression to match time-estimate tags. Compile it here to avoid
      # repetition later on.
      options.timetagsregex_compiled = Regexp.compile(options.timetagsregex) if options.timetagsregex
      # Structure to keep track of already create items
      # These hashes are indexed by Things node ID (node.id_). Each element
      # contains a hash with two elements:
      #     :things_node - pointer to the corresponding AS node in Things
      #     :thl_node    - pointer to the corresponding AS node in THL
      @cache_nodes = {}

      # Cache of which items are contained in each focus (Inbox, etc.)
      # Indexed by focus name, value is a hash with elements keyed by the
      # id_ of each node that belongs to that focus. Existence of the key
      # indicates existence in the focus.
      @cache_focus = {}
    end

    # Get the type of the THL node that corresponds to the given Things node,
    # depending on the options specified
    def thl_node_type(node)
      case node
      when Symbol
        type=node
      else
        type=node.type
      end
      Constants::STRUCTURES[options.structure][type][0]
    end

    # Get the name/title for a THL node.
    def thl_node_name(node)
      node.properties_.get[Constants::TITLEPROP[node.class_.get]]
    end

    def props_from_node(node)
      newprops={}
      # Process the properties, according to how the mapping is specified in STRUCTURES
      pm=Constants::STRUCTURES[options.structure][node.type][1]
      proptoset=nil
      pm.keys.each do |k|
        case pm[k]
        when Symbol
          proptoset=pm[k]
          value=node.node.properties_.get[k]
          newprops[proptoset] = value if value && value != :missing_value
        when Array
          proptoset=pm[k][0]
          value=pm[k][1][node.node.properties_.get[k]]
          newprops[proptoset] = value if value && value != :missing_value
        when Hash
          value = node.node.properties_.get[k]
          if value && value != :missing_value
            proptoset = pm[k][value]
            if proptoset
              newprops[proptoset] = true
            end
          end
        else
          puts "Invalid class for pm[k]=#{pm[k]} (#{pm[k].class})"
        end
        puts "Mapping node.#{k} (#{node.node.properties_.get[k]}) to newprops[#{proptoset}]=#{newprops[proptoset]}" if $DEBUG
      end
      # Do any necesary postprocessing
      postproc=Constants::STRUCTURES[options.structure][node.type][2]
      if postproc
        puts "Calling post-processor #{postproc.to_s} with newprops=#{newprops.inspect}" if $DEBUG
        postproc.call(node, newprops, self)
        puts "After post-processor: #{newprops.inspect}" if $DEBUG
      end
      return newprops
    end

    def loose_tasks_name(parent)
      if parent == top_level_node
        "Loose tasks"
      else
        thl_node_name(parent) + " - loose tasks"
      end
    end

    # Find or create a list or a folder inside the given parent (or the top-level folders group if not given)
    def find_or_create(what, name, parent = @thl.folders_group.get)
      unless what == :list || what == :folder
        raise "find_or_create: 'what' parameter has to be :list or :folder"
      end
      puts "parent of #{name} = #{parent}" if $DEBUG
      if parent.class_.get != :folder
        raise "find_or_create: parent is not a folder, it's a #{parent.class_.get}"
      else
        if parent.groups[name].exists
          parent.groups[name].get
        else
          parent.end.make(:new => what, :with_properties => {:name => name})
        end
      end
    end

    def new_folder(name, parent = @thl.folders_group.get)
      parent.end.make(:new => :folder,
                      :with_properties => { :name => name })
    end

    # Return the provided top level node, or the folders group if the option is not specified
    def top_level_node
      return @thl.folders_group.get unless options.toplevel

      unless @top_level_node
        # Create the top-level node if we don't have it cached yet
        @top_level_node=new_folder(options.toplevel)
      end
      @top_level_node
    end

    # Create (if necessary) and return an appropriate THL container
    # for a given top-level Things focus.
    # If --top-level-folder is specified, all of them are simply
    # folders inside that folder.
    # Otherwise:
    #   Inbox => Inbox
    #   Next  => default top level node
    #   Scheduled, Someday => correspondingly-named top-level folders
    #   Logbook => 'Completed' top-level folder
    #   Projects => 'Projects' list if --projects-as-tasks
    #            => 'Projects' folder if --projects-folder was specified
    #            => default top level node otherwise
    #   Trash   => ignore
    #   Today   => ignore
    def top_level_for_focus(focusnames)
      # We loop through all the focus names given, and return the first
      # one that produces a non-nil container
      focusnames.each do |focusname|
        result = if options.toplevel
                   case focusname
                   when 'Trash', 'Today'
                     nil
                   when 'Inbox', 'Next'
                     find_or_create(:list, focusname, top_level_node)
                   when 'Scheduled', 'Logbook'
                     find_or_create((thl_node_type(:project) == :task) ? :list : :folder, focusname, top_level_node)
                   when 'Someday'
                     find_or_create(:folder, focusname, top_level_node)
                   when 'Projects'
                     if thl_node_type(:project) == :task
                       find_or_create(:list, options.projectsfolder || 'Projects', top_level_node)
                     else
                       if options.projectsfolder
                         find_or_create(:folder, options.projectsfolder, top_level_node)
                       else
                         top_level_node
                       end
                     end
                   else 
                     puts "Invalid focus name: #{focusname}"
                     top_level_node
                   end
                 else
                   # That was easy. Now for the more complicated part.
                   case focusname
                   when 'Inbox'
                     thl.inbox.get
                   when 'Next'
                     top_level_node
                   when 'Scheduled', 'Logbook'
                     find_or_create((thl_node_type(:project) == :task) ? :list : :folder, focusname, top_level_node)
                   when 'Someday'
                     find_or_create(:folder, focusname, top_level_node)
                   when 'Projects'
                     if thl_node_type(:project) == :task
                       find_or_create(:list, options.projectsfolder || 'Projects', top_level_node)
                     else
                       if options.projectsfolder
                         find_or_create(:folder, options.projectsfolder, top_level_node)
                       else
                         top_level_node
                       end
                     end
                   when 'Trash', 'Today'
                     nil
                   else 
                     puts "Invalid focus name: #{focusname}"
                     top_level_node
                   end
                 end
        return result if result
      end
      nil
    end

    # Get the top-level focus for a node. If it's not directly contained
    # in a focus, check its project and area, if any.
    def top_level_for_node(node)
      # Areas are always contained at the top level, unless they
      # are suspended
      if node.type == :area
        if node.suspended
          return top_level_for_focus('Someday')
        else
          if options.areasfolder
            return find_or_create(:folder, options.areasfolder || 'Areas', top_level_node)
          else
            return top_level_node
          end
        end
      end

      # Else, find if the node is contained in a top-level focus...
      foci=focus_of(node)
      # ...if not, look at its project and area
      if foci.empty?
        if node.project?
          tl=top_level_for_node(node.project)
          if !tl && node.area?
            tl=top_level_for_node(node.area)
          end
        elsif node.area?
          tl=top_level_for_node(node.area)
        end
        return tl
      end
      top_level_for_focus(foci)
    end

    # See if we have processed a node already - in that case return
    # the cached THL node. Otherwise, invoke the process() function
    # on it, which will put it in the cache.
    def get_cached_or_process(node)
      node_id=node.id_
      if @cache_nodes.has_key?(node_id)
        @cache_nodes[node_id][:thl_node]
      else
        # If we don't have the corresponding node cached yet, do it now
        process(node)
      end
    end

    # Create if necessary and return an appropriate THL container
    # object for the new node, according to the node's class and
    # options selected.  A task in THL can only be contained in a list
    # or in another task. So if parent is a folder and note is a task,
    # we need to find or create an auxiliary list to contain it.
    def container_for(node)
      # If its top-level container is nil, it means we need to skip this node
      tlcontainer=top_level_for_node(node)
      return nil unless tlcontainer

      # Otherwise, run through the process
      container = case node.type
                  when :area
                    tlcontainer
                  when :project
                    if options.areas && (options.structure != :projects_areas_as_lists)  && node.area?
                      get_cached_or_process(node.area)
                    else
                      tlcontainer
                    end
                  when :selected_to_do
                    if node.project?
                      get_cached_or_process(node.project)
                    elsif node.area? && options.areas
                      get_cached_or_process(node.area)
                    else
                      # It's a loose task
                      tlcontainer
                    end
                  else
                    raise "Invalid Things node type: #{node.type}"
                  end

      # Now we check the container type. Tasks can only be contained in lists,
      # so if the container is a folder, we have to create a list to hold the task
      if container && (container.class_.get == :folder) && (thl_node_type(node) == :task)
        if node.type == :project
          find_or_create(:list, options.projectsfolder || 'Projects', container)
        else
          find_or_create(:list, loose_tasks_name(container), container)
        end
      else
        container
      end
    end

    def create_in_thl(node, parent)
      if (parent)
        new_node_type = thl_node_type(node)
        new_node_props = props_from_node(node)
        additional_nodes = new_node_props.delete(:__newnodes__)
        result=parent.end.make(:new => new_node_type,
                               :with_properties => new_node_props )
        if node.type == :area || node.type == :project
          @cache_nodes[node.id_]={}
          @cache_nodes[node.id_][:things_node] = node
          @cache_nodes[node.id_][:thl_node] = result
        end
        # Add new nodes
        if additional_nodes
          additional_nodes.each do |n|
            result.end.make(n)
          end
        end
        return result
      else
        parent
      end
    end

    # Process a single node. Returns the new THL node.
    def process(node)
      return unless node
      # Skip if we have already processed it
      return if @cache_nodes.has_key?(node.id_)
      # Areas don't have status, so we skip the check
      unless node.type == :area
        return if ( node.status == :completed || node.status == :canceled ) && !(options.completed)
      end

      container=container_for(node)
      puts "Container for #{node.name}: #{container}" if $DEBUG
      unless container
        puts "Skipping trashed task '#{node.name}'" unless options.quiet
        return
      end
      
      unless (options.quiet) 
        bullet  = (node.type == :area) ? "*" : ((node.status == :completed) ? "✓" : (node.status == :canceled) ? "×" : "-")
        puts bullet + " " + node.name
      end

      newnode=create_in_thl(node, container)
    end

    # Get all the focus names
    def get_focusnames(all=false)
      # Get only top-level items of type :list (areas are also there, but with type :area) unless all==true
      @cached_focusnames||=things.lists.get.select {|l| all || l.class_.get == :list }.map { |focus| focus.name.get }
    end

    # Create the focus caches
    def create_focuscaches
      get_focusnames.each { |focus|
        puts "Creating focus cache for #{focus}..." if $DEBUG
        @cache_focus[focus] = {}
        next if focus == "Logbook" && !options.completed
        things.lists[focus].to_dos.get.each { |t|
          @cache_focus[focus][t.id_.get] = true
        }
        puts "   Cache: #{@cache_focus[focus].inspect}" if $DEBUG
      }
    end

    # Get the focuses in which a task is visible
    def focus_of(node)
      result=[]
      get_focusnames.each { |focus|
        if in_focus?(focus, node)
          result.push(focus)
        end
      }
      if node.type == :area && node.suspended
        result.push('Someday')
      end
      result
    end

    # Check if a node is in a certain focus
    # Node can be a ThingsNode, and AS node, or a node ID
    def in_focus?(focus, node)
      unless @cache_focus[focus]
        create_focuscaches
      end
      case node
      when ThingsNode
        key = node.id_
      when Appscript::Reference
        key = node.id_.get
      when String
        key = node
      else
        puts "Unknown node object type: #{node.class}"
        return nil
      end
      return @cache_focus[focus].has_key?(key)
    end

    ###-------------------------------------------------------------------
    ### Methods to fix new nodes - called from the postproc block in STRUCTURES

    # Things sets both 'completion_date' and 'cancellation_date'
    # for both completed and canceled tasks, which confuses THL,
    # so we delete the one that should not be there.
    def fix_completed_canceled(node,prop)
      if prop[:completed_date] && prop[:canceled_date]
        if prop[:canceled]
          prop.delete(:completed)
          prop.delete(:completed_date)
        else
          prop.delete(:canceled)
          prop.delete(:canceled_date)
        end
      end
    end

    # Archive completed/canceled if requested
    def archive_completed(prop)
      prop[:archived] = true if options.archivecompleted && (prop[:completed] || prop[:canceled])
    end

    # Process tags
    def process_tags(node, prop, inherit_project_tags, inherit_area_tags)
      tasktags = node.tags.map {|t| t.name }
      if inherit_project_tags
        # Merge project and area tags
        if node.project?
          tasktags |= node.project.tags.map {|t| t.name }
          if options.areas && node.project.area?
            tasktags |= node.project.area.tags.map {|t| t.name }
          end
        end
      end
      if options.areas && node.area? && inherit_area_tags
        tasktags |= node.area.tags.map {|t| t.name }
      end
      unless tasktags.empty?
        # First process time-estimate tags if needed
        if options.timetags
          # Valid time tags will be deleted from the tags list
          tasktags=tasktags.delete_if do |t|
            if data=options.timetagsregex_compiled.match(t)
              timeestimate = nil
              # If the regex includes only one group, it is assumed to be
              # the time in minutes. If it includes two groups, the second
              # group specifies the time unit, as defined in Constants::TIMEUNITS
              case data.size
              when 0
                puts "Invalid time tags regex, does not return any groups: #{options.timetagsregex_compiled.to_s}"
              when 1
                # Assumed to be in minutes, timeestimate is in seconds
                timeestimate = data[1].to_i * 60
              else
                # Second one is the units - the rest are ignored
                timeunit=Constants::TIMEUNITS[data[2]]
                if !timeunit
                  puts "Invalid time estimate tag, I could not match the time unit: '#{t}'"
                else 
                  timeestimate = data[1].to_i * timeunit
                end
              end
              if timeestimate
                prop[:estimated_time] = timeestimate
              end
            end
          end
        end
        prop[:title] = [prop[:title], tasktags.map do |t|
                          if options.contexttagsregex_compiled &&
                              options.contexttagsregex_compiled.match(t)
                            # Contexts cannot have spaces, we also remove any initial @'s before adding our own.
                            "@" + t.gsub(/^@+/, "").gsub(/ /, '_')
                          else
                            "/" + t + (t.index(" ")?"/":"")
                          end
                        end].join(' ')
      end
    end

    # Check if node is in the Today list
    def check_today(node, prop)
      if in_focus?('Today', node)
        prop[:start_date] = Time.parse('today at 00:00')
      end
    end

    def add_extra_node(prop, newnode)
      prop[:__newnodes__] = [] unless prop.has_key?(:__newnodes__)
      prop[:__newnodes__].push(newnode)
    end

    def hextostring(hexstr)
      [hexstr.delete(" ")].pack("H*")
    end

    def aliastostring(node)
      hextostring((node/'alias').inner_text)
    end

    # Process Things notes before adding them to THL.
    def convert_notes(notes)
      return unless notes
      # First, parse the notes as XML and extract the contents of the <note> tag
      note_html = (Hpricot.XML(notes)/'/note').inner_html
      # Then parse the HTML
      html = Hpricot(note_html)
      # Then swap any <alias> tags with their unencoded content
      # TODO: this is a hack - it would be much better to understand the binary structure of the <alias> tag.
      while html.at('alias')
        html.at('alias').swap( aliastostring(html).gsub(/^.*\000\022\000.(.*?)\000.*$/m, 'file:///\1') )
      end
      # Finally return the HTML in "plain text" format, which shows the links in brackets
      html.to_plain_text
    end

    # Add a new task containing project notes when the project is a THL list,
    # since THL lists cannot have notes
    def add_list_notes(node, prop)
      new_node_type = thl_node_type(node)
      # Process notes only for non-areas
      if (node.type != :area)
        # If the node has notes but the THL node is a list, add the notes as a task in there
        # If the node has notes but the THL node is a folder (this shouldn't happen), print a warning
        if node.notes? && new_node_type == :list
          newnode = {
            :new => :task,
            :with_properties => { :title => "Notes for '#{prop[:name]}'", :notes => convert_notes(node.notes) }}
          # Mark as completed if the project is completed
          if node.status == :completed || node.status == :canceled
            newnode[:with_properties][:completed] = true
            archive_completed(newnode[:with_properties])
          end
          add_extra_node(prop, newnode)
        end
        if node.notes? && new_node_type == :folder
          $stderr.puts "Error: cannot transfer notes into new folder: #{node.notes}"
        end
      end
    end

    # Transfer processed notes
    def add_notes(node, prop)
      prop[:notes] = convert_notes(node.notes) if node.notes?
    end

    # When projects are lists, if the project has a due date, we add a bogus task to it
    # to represent its due date, since lists in THL cannot have due dates.
    def add_project_duedate(node, prop)
      new_node_type = thl_node_type(node)
      return unless node.type == :project && new_node_type == :list && node.due_date?

      # Create the new node
      newnode = {
        :new => :task,
        :with_properties => { :title => "Due date for '#{prop[:name]}'", :due_date => node.due_date }
      }
      add_extra_node(prop, newnode)
    end

  end #### class Converter

  ####################################################################

  # Return a structure with the default option values
  def Things2THL.default_options
    options=OpenStruct.new
    options.completed = false
    options.database = nil
    options.structure = nil
    options.areas = true
    options.quiet = false
    options.archivecompleted = true
    options.projectsfolder = nil
    options.areasfolder = nil
    options.contexttagsregex = '^@'
    options.timetagsregex = '^(\d+)(min|sec|hr)$'
    options.timetags = false
    return options
  end

  def Things2THL.new(opt_struct = nil, things_db = nil, thl_location = nil)
    Converter.new(opt_struct, things_db, thl_location)
  end
end

######################################################################
# For debugging and testing

if $0 == __FILE__
  c=Things2THL.new
  th=c.things
  thl=c.thl
  true
end
