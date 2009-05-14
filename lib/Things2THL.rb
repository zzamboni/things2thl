# -*- coding: utf-8 -*-

#require File.join(File.dirname(__FILE__), *%w".. .. things-rb lib things")
require "ostruct"
require 'time'
begin; require 'rubygems'; rescue LoadError; end
require 'appscript'; include Appscript

######################################################################

module Things2THL
  module Version
    MAJOR  = 0
    MINOR  = 1

    STRING = [MAJOR, MINOR].join(".")
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
                              :status => {
                                :completed => :completed,
                                :canceled  => :canceled,
                              },
                              :notes => :notes,
                            },
                            Proc.new {|node,prop,obj|
                              obj.fix_completed_canceled(node, prop)
                              obj.archive_completed(prop)
                              obj.add_tags(node, prop, true, true)
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
                       :status => {
                         :completed => :completed,
                         :canceled  => :canceled,
                       },
                       :notes => :notes,
                     },
                     Proc.new {|node,prop,obj|
                       obj.fix_completed_canceled(node, prop)
                       obj.archive_completed(prop)
                       obj.add_tags(node, prop, false, true)
                     }
                    ],
        :selected_to_do => [:task,
                            {
                              :name => :title,
                              :creation_date => :created_date,
                              :due_date => :due_date,
                              :completion_date => :completed_date,
                              :cancellation_date => :canceled_date,
                              :status => {
                                :completed => :completed,
                                :canceled  => :canceled,
                              },
                              :notes => :notes,
                            },
                            Proc.new {|node,prop,obj|
                              obj.fix_completed_canceled(node, prop)
                              obj.archive_completed(prop)
                              obj.add_tags(node, prop, false, true)
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

    def initialize(node)
      @node = node
      (node.properties + node.elements).each do |prop|
        case prop
        # For area, project and some others, convert the result to a ThingsNode as well
        when 'area', 'project', 'areas', 'projects', 'parent_tag', 'delegate'
          ThingsNode.class_eval <<-EOF
          def #{prop}
            value=node.#{prop}.get
            case value
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
            value=node.#{prop}.get
            case value
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
            value=node.#{prop}.get
            value=nil if value==:missing_value
            value
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
      @options=opt_struct || OpenStruct.new
      thingsappname=things_location || 'Things'
      thlappname=thl_location || 'The Hit List'
      begin
        @things = Appscript.app(thingsappname)
        @thl = Appscript.app(thlappname)
      rescue ApplicationNotFoundError => e
        puts "I could not open one of the needed applications: #{e.message}"
        exit(1)
      end

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
      Constants::STRUCTURES[options.structure][node.type][0]
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
        puts "Mapping node.#{k} (#{node.node.properties_.get[k]}) to newprops[#{proptoset}]=#{newprops[proptoset]}"
      end
      # Do any necesary postprocessing
      postproc=Constants::STRUCTURES[options.structure][node.type][2]
      if postproc
        puts "Calling post-processor #{postproc.to_s} with newprops=#{newprops.inspect}"
        postproc.call(node, newprops, self)
        puts "After post-processor: #{newprops.inspect}"
      end
      return newprops
    end

    def loose_tasks_name(parent)
      return parent.properties_.get[Constants::TITLEPROP[parent.class_.get]] + " - loose tasks"
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
          return parent.groups[name].get
        else
          return parent.end.make(:new => what, :with_properties => {:name => name})
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

    # Create if necessary and return an appropriate THL container
    # object for the new node, according to the node's class and
    # options selected.  A task in THL can only be contained in a list
    # or in another task. So if parent is a folder and note is a task,
    # we need to find or create an auxiliary list to contain it.
    def container_for(node)
      case node.type
      when :area
        # If a top-level folder was specified, use that, otherwise use the THL folders group
        container=top_level_node
      when :project
        if options.areas && node.area?
          area_id=node.area.id_
          if @cache_nodes.has_key?(area_id)
            container=@cache_nodes[area_id][:thl_node]
          else
            # If we don't have the corresponding area cached yet, do it now
            container=process(node.area)
          end
        else
          if options.structure == :projects_as_tasks
            container=find_or_create(:list, 'Projects', top_level_node)
          else
            container=top_level_node
          end
        end
      when :selected_to_do
        if node.project?
          project_id=node.project.id_
          if @cache_nodes.has_key?(project_id)
            container=@cache_nodes[project_id][:thl_node]
          else
            # If we don't have the corresponding project cached yet, do it now
            container=process(node.project)
          end
        elsif node.area? && options.areas
          area_id=node.area.id_
          if @cache_nodes.has_key?(area_id)
            container=@cache_nodes[area_id][:thl_node]
          else
            # If we don't have the corresponding area cached yet, do it now
            container=process(node.area)
          end
        else
          # It's a loose task
          container=find_or_create(:list, 'Loose tasks', top_level_node)
        end
      else
        raise "Invalid Things node type: #{node.type}"
      end

      # Now we check the container type. Tasks can only be contained in lists,
      # so if the container is a folder, we have to create a list to hold the task
      if container && (container.class_.get == :folder) && (thl_node_type(node) == :task)
        if node.type == :project
          find_or_create(:list, 'Projects', container)
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

    def traverse(node, level = 0, parent=nil)
      return unless node
      return if ( node.status == :completed || node.status == :canceled ) && !(options.completed)
      newnode=nil
      unless (options.quiet) 
        bullet  = (node.status == :completed) ? "✓" : (node.status == :canceled) ? "×" : "-"
        puts bullet + " " + node.name + " (#{node.type})" 
      end
      unless (options.dryrun || parent == nil)
        newnode=create_in_thl(node, parent)
      end
      if node.to_dos?
        node.to_dos.map do |child|
          traverse(child, level + 1, newnode)
        end
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
      raise "Could not get a container for node '#{node.name}'" unless container
      
      unless (options.quiet) 
        bullet  = (node.type == :area) ? "*" : ((node.status == :completed) ? "✓" : (node.status == :canceled) ? "×" : "-")
        puts bullet + " " + node.name + " (#{node.type})" 
      end

      unless (options.dryrun)
        newnode=create_in_thl(node, container)
      end
    end

    # Get all the focus names
    def get_focusnames
      # Get only top-level items of type :list (areas are also there, but with type :area)
      things.lists.get.select {|l| l.class_.get == :list }.map { |focus| focus.name.get }
    end

    # Create the focus caches
    def create_focuscaches
      get_focusnames.each { |focus|
        puts "Creating focus cache for #{focus}..."
        @cache_focus[focus] = {}
        things.lists[focus].to_dos.get.each { |t|
          @cache_focus[focus][t.id_.get] = true
        }
        puts "   Cache: #{@cache_focus[focus].inspect}"
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

    # Add tags to title
    def add_tags(node, prop, inherit_project_tags, inherit_area_tags)
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
        prop[:title] = [prop[:title], tasktags.map {|t| "/" + t + (t.index(" ")?"/":"") }].join(' ')
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
            :with_properties => { :title => "Notes for '#{prop[:name]}'", :notes => node.notes }}
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

  def Things2THL.new(opt_struct = nil, things_db = nil, thl_location = nil)
    Converter.new(opt_struct, things_db, thl_location)
  end
end
