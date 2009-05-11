# -*- coding: utf-8 -*-

#require File.join(File.dirname(__FILE__), *%w".. .. things-rb lib things")
require "ostruct"
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
    # Elements are: <Things item> => <THL item>
    STRUCTURES = {
      :projects_as_lists => { 
        :area => :folder,
        :project => :list,
        :selected_to_do => :task },
      :projects_as_tasks => {
        :area => :list,
        :project => :task,
        :selected_to_do => :task  }
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

      # Structures to keep track of already create items
      # These hashes are indexed by Things node ID (node.id_). Each element
      # contains a hash with two elements:
      #     :things_node - pointer to the corresponding AS node in Things
      #     :thl_node    - pointer to the corresponding AS node in THL
      @cache_nodes = {}

    end

    # Get the type of the THL node that corresponds to the given Things node,
    # depending on the options specified
    def thl_node_type(node)
      Constants::STRUCTURES[options.structure][node.type]
    end

    def props_from_node(node)
      newprops={}
      # First the title, using the appropriate tag according to task type
      newprops[Constants::TITLEPROP[thl_node_type(node)]] = node.name
      # Also transfer notes. Only tasks can have notes in THL, and areas in Things don't have notes
      newprops[:notes] = node.notes if node.type != :area && node.notes? && thl_node_type(node) == :task
      return newprops
    end

    def loose_tasks_name(parent)
      return parent.properties_.get[Constants::TITLEPROP[parent.class_.get]] + " - loose tasks"
    end

    def find_or_create_list(name, parent = @thl.folders_group.get)
      # Get list of children
      if parent.class_.get != :folder
        return nil
      else
        lists = parent.lists.get.map { |l| l.name.get }
        n = lists.index(name)
        if n
          return parent.lists.get[n]
        else
          return parent.end.make(:new => :list, :with_properties => {:name => name})
        end
      end
    end

    def new_folder(name, parent = @thl.folders_group.get)
      parent.end.make(:new => :folder,
                      :with_properties => { :name => name })
    end

    def top_level_node
      return nil unless options.toplevel

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
        if options.toplevel
          container=top_level_node
        else
          container=@thl.folders_group.get
        end
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
          if options.toplevel
            container=top_level_node
          else
            container=@thl.folders_group.get
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
          container=find_or_create_list('Loose tasks', top_level_node)
        end
      else
        raise "Invalid Things node type: #{node.type}"
      end

      # Now we check the container type. Tasks can only be contained in lists,
      # so if the container is a folder, we have to create a list to hold the task
      if container && (container.class_.get == :folder) &&
          (Constants::STRUCTURES[options.structure][node.type] == :task)
        if node.type == :project
          find_or_create_list('Projects', container)
        else
          find_or_create_list(loose_tasks_name(container), container)
        end
      else
        container
      end
    end

    def create_in_thl(node, parent)
      if (parent)
        new_node_type = Constants::STRUCTURES[options.structure][node.type]
        result=parent.end.make(:new => new_node_type,
                               :with_properties => props_from_node(node) )
        if node.type == :area || node.type == :project
          @cache_nodes[node.id_]={}
          @cache_nodes[node.id_][:things_node] = node
          @cache_nodes[node.id_][:thl_node] = result
        end
        # Process notes only for non-areas
        if (node.type != :area)
          # If the node has notes but the THL node is a list, add the notes as a task in there
          # If the node has notes but the THL node is a folder (this shouldn't happen), print a warning
          if node.notes? && new_node_type == :list
            result.end.make(:new => :task, :with_properties => { :title => "Notes for this list from Things", :notes => node.notes })
          end
          if node.notes? && new_node_type == :folder
            $stderr.puts "Error: cannot transfer notes into new folder: #{node.notes}"
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

  end #### class Converter

  ####################################################################

  def Things2THL.new(opt_struct = nil, things_db = nil, thl_location = nil)
    Converter.new(opt_struct, things_db, thl_location)
  end
end
