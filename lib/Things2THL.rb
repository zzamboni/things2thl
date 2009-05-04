# -*- coding: utf-8 -*-

require File.join(File.dirname(__FILE__), *%w".. .. things-rb lib things")
require "ostruct"
begin; require 'rubygems'; rescue LoadError; end
require 'appscript'

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
        :task => :task },
      :projects_as_tasks => {
        :area => :list,
        :project => :task,
        :task => :task  }
    }

    # For some reason some entities in THL use "title", others use "name"
    TITLEPROP = {
      :folder => :name,
      :list => :name,
      :task => :title
    }
  end

  ####################################################################

  class Converter
    attr_accessor :options, :things, :thl

    def initialize(opt_struct, things_db = nil, thl_location = nil)
      @options=opt_struct
      @things = Things.new(:database => things_db)
      appname=thl_location || 'The Hit List'
      @thl = Appscript.app(appname)
    end

    def props_from_node(node, new_node_type)
      newprops={}
      # First the title, using the appropriate tag according to task type
      newprops[Things2THL::Constants::TITLEPROP[Things2THL::Constants::STRUCTURES[options.structure][node.type]]] = node.title
      # Also transfer notes. Only tasks can have notes in THL
      newprops[:notes] = node.notes if node.notes? && new_node_type == :task
      return newprops
    end

    def loose_tasks_name(parent)
      return parent.properties_.get[Things2THL::Constants::TITLEPROP[parent.class_.get]] + " - loose tasks"
    end

    def find_or_create_list(parent, name)
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

    # Create if necessary and return an appropriate THL container object
    # for the new node.  A task in THL can only be contained in a list or
    # in another task. So if parent is a folder and note is a task, we
    # need to find or create an auxiliary list to contain it.
    def container_for(node, parent)
      if parent && (parent.class_.get == :folder) &&
          (Things2THL::Constants::STRUCTURES[options.structure][node.type] == :task)
        return find_or_create_list(parent, loose_tasks_name(parent))
      else
        return parent
      end
    end

    def create_in_thl(node, parent)
      if (parent)
        new_node_type = Things2THL::Constants::STRUCTURES[options.structure][node.type]
        result=container_for(node, parent).end.make(:new => new_node_type,
                                                    :with_properties => props_from_node(node, new_node_type) )
        # If the node has notes but the THL node is a list, add the notes as a task in there
        # If the node has notes but the THL node is a folder (this shouldn't happen), print a warning
        if node.notes? && new_node_type == :list
          result.end.make(:new => :task, :with_properties => { :title => "Notes for this list from Things", :notes => node.notes })
        end
        if node.notes? && new_node_type == :folder
          $stderr.puts "Error: cannot transfer notes into new folder: #{node.notes}"
        end
        return result
      else
        parent
      end
    end

    def traverse(node, level = 0, parent=nil)
      return unless node
      return if ( node.completed? || node.canceled? ) && !(options.completed)
      newnode=nil
      unless (options.quiet) 
        bullet  = node.completed? ? "✓" : node.canceled? ? "×" : "-"
        puts "    " * level + bullet + " " + node.title + " (#{node.type})" 
      end
      unless (options.dryrun || parent == nil)
        newnode=create_in_thl(node, parent)
      end
      if node.children?
        node.children.map do |child|
          traverse(child, level + 1, newnode)
        end
      end
    end

  end

  def Things2THL.new(opt_struct, things_db = nil, thl_location = nil)
    Converter.new(opt_struct, things_db, thl_location)
  end
end
