# This file is part of the ruby-dbus project
# Copyright (C) 2007 Arnaud Cornet and Paul van Tilburg
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License, version 2.1 as published by the Free Software Foundation.
# See the file "COPYING" for the exact licensing terms.

require "thread"
require_relative "core_ext/class/attribute"

module DBus
  # Exported object type
  # = Exportable D-Bus object class
  #
  # Objects that are going to be exported by a D-Bus service
  # should inherit from this class. At the client side, use {ProxyObject}.
  class Object
    # The path of the object.
    attr_reader :path
    # The interfaces that the object supports. Hash: String => Interface
    my_class_attribute :intfs
    self.intfs = {}

    # The service that the object is exported by.
    attr_writer :service

    @@cur_intf = nil # Interface
    @@intfs_mutex = Mutex.new

    # Create a new object with a given _path_.
    # Use Service#export to export it.
    def initialize(path)
      @path = path
      @service = nil
    end

    # Dispatch a message _msg_ to call exported methods
    def dispatch(msg)
      case msg.message_type
      when Message::METHOD_CALL
        reply = nil
        begin
          if !intfs[msg.interface]
            raise DBus.error("org.freedesktop.DBus.Error.UnknownMethod"),
                  "Interface \"#{msg.interface}\" of object \"#{msg.path}\" doesn't exist"
          end
          meth = intfs[msg.interface].methods[msg.member.to_sym]
          if !meth
            raise DBus.error("org.freedesktop.DBus.Error.UnknownMethod"),
                  "Method \"#{msg.member}\" on interface \"#{msg.interface}\" of object \"#{msg.path}\" doesn't exist"
          end
          methname = Object.make_method_name(msg.interface, msg.member)
          retdata = method(methname).call(*msg.params)
          retdata = [*retdata]

          reply = Message.method_return(msg)
          meth.rets.zip(retdata).each do |rsig, rdata|
            reply.add_param(rsig.type, rdata)
          end
        rescue StandardError => ex
          dbus_msg_exc = msg.annotate_exception(ex)
          reply = ErrorMessage.from_exception(dbus_msg_exc).reply_to(msg)
        end
        @service.bus.message_queue.push(reply)
      end
    end

    # Select (and create) the interface that the following defined methods
    # belong to.
    def self.dbus_interface(s)
      @@intfs_mutex.synchronize do
        @@cur_intf = intfs[s]
        if !@@cur_intf
          @@cur_intf = Interface.new(s)
          # As this is a mutable class_attr, we cannot use
          #   self.intfs[s] = @@cur_intf                      # Hash#[]=
          # as that would modify parent class attr in place.
          # Using the setter lets a subclass have the new value
          # while the superclass keeps the old one.
          self.intfs = intfs.merge(s => @@cur_intf)
        end
        yield
        @@cur_intf = nil
      end
    end

    # Dummy undefined interface class.
    class UndefinedInterface < ScriptError # rubocop:disable Lint/InheritException
      def initialize(sym)
        super "No interface specified for #{sym}"
      end
    end


    # A read-write property accessing an instance variable.
    # A combination of attr_accessor and {.dbus_accessor}.
    #
    # PropertiesChanged signal will be emitted whenever `foo_bar=` is used
    # but not when @foo_bar is written directly.
    #
    # @param ruby_name [Symbol] :foo_bar is exposed as FooBar;
    #   use dbus_name to override
    # @param type a signature like "s" or "a(uus)" or Type::STRING
    # @param dbus_name [String] if not given it is made
    #   by CamelCasing the ruby_name. foo_bar becomes FooBar
    #   to convert the Ruby convention to the DBus convention.
    # @return [void]
    def self.dbus_attr_accessor(ruby_name, type, dbus_name: nil)
      attr_accessor(ruby_name, dbus_name)
      dbus_accessor(ruby_name, type, dbus_name)
    end

    # A read-only property accessing an instance variable.
    # A combination of attr_reader and {.dbus_reader}.
    #
    # PropertiesChanged: You should also call FIXME Class#method(args) whenever
    # the underlying value changes to emit PropertiesChanged.
    #
    # @param  (see .dbus_attr_accessor)
    # @return (see .dbus_attr_accessor)
    def self.dbus_attr_reader(ruby_name, type, dbus_name: nil)
      attr_reader(ruby_name, dbus_name)
      dbus_reader(ruby_name, type, dbus_name)
    end

    # A write-only property accessing an instance variable.
    # A combination of attr_writer and {.dbus_writer}.
    #
    # @param  (see .dbus_attr_accessor)
    # @return (see .dbus_attr_accessor)
    def self.dbus_attr_writer(ruby_name, type, dbus_name: nil)
      attr_writer(ruby_name, dbus_name)
      dbus_writer(ruby_name, type, dbus_name)
    end

    # A read-write property using a pair of reader/writer methods
    # (which must already exist).
    # (To directly access an instance variable, use {.dbus_attr_accessor} instead)
    #
    # Uses {.dbus_watcher} to set up the PropertiesChanged signal.
    #
    # @param  (see .dbus_attr_accessor)
    # @return (see .dbus_attr_accessor)
    def self.dbus_accessor(ruby_name, type, dbus_name: nil)
    end

    # A read-only property accessing a reader method (which must already exist).
    # (To directly access an instance variable, use {.dbus_attr_reader} instead)
    #
    # PropertiesChanged: You should also call FIXME Class#method(args) whenever
    # the underlying value changes to emit PropertiesChanged.
    #
    # @param  (see .dbus_attr_accessor)
    # @return (see .dbus_attr_accessor)
    def self.dbus_reader(ruby_name, type, dbus_name: nil)
    end

    # A write-only property accessing a writer method (which must already exist).
    # (To directly access an instance variable, use {.dbus_attr_writer} instead)
    #
    # Uses {.dbus_watcher} to set up the PropertiesChanged signal.
    #
    # @param  (see .dbus_attr_accessor)
    # @return (see .dbus_attr_accessor)
    def self.dbus_writer(ruby_name, type, dbus_name: nil)
    end

    # Enables automatic sending of the PropertiesChanged signal.
    # For *ruby_name* `foo_bar`, wrap `foo_bar=` so that it sends
    # the signal for FooBar.
    # The original version remains as #_original_foo.
    #
    # @param ruby_name [Symbol] :foo_bar and :foo_bar= both mean the same thing
    # @param dbus_name [String] if not given it is made
    #   by CamelCasing the ruby_name. foo_bar becomes FooBar
    #   to convert the Ruby convention to the DBus convention.
    # @return [void]
    def self.dbus_watcher(ruby_name, dbus_name: nil)
    end

    # Defines an exportable method on the object with the given name _sym_,
    # _prototype_ and the code in a block.
    def self.dbus_method(sym, protoype = "", &block)
      raise UndefinedInterface, sym if @@cur_intf.nil?
      @@cur_intf.define(Method.new(sym.to_s).from_prototype(protoype))
      define_method(Object.make_method_name(@@cur_intf.name, sym.to_s), &block)
    end

    # Emits a signal from the object with the given _interface_, signal
    # _sig_ and arguments _args_.
    def emit(intf, sig, *args)
      @service.bus.emit(@service, self, intf, sig, *args)
    end

    # Defines a signal for the object with a given name _sym_ and _prototype_.
    def self.dbus_signal(sym, protoype = "")
      raise UndefinedInterface, sym if @@cur_intf.nil?
      cur_intf = @@cur_intf
      signal = Signal.new(sym.to_s).from_prototype(protoype)
      cur_intf.define(Signal.new(sym.to_s).from_prototype(protoype))
      define_method(sym.to_s) do |*args|
        emit(cur_intf, signal, *args)
      end
    end

    ####################################################################

    # Helper method that returns a method name generated from the interface
    # name _intfname_ and method name _methname_.
    # @api private
    def self.make_method_name(intfname, methname)
      "#{intfname}%%#{methname}"
    end
  end
end
