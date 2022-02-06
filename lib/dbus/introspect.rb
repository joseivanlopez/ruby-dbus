# dbus/introspection.rb - module containing a low-level D-Bus introspection implementation
#
# This file is part of the ruby-dbus project
# Copyright (C) 2007 Arnaud Cornet and Paul van Tilburg
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License, version 2.1 as published by the Free Software Foundation.
# See the file "COPYING" for the exact licensing terms.

module DBus
  # Regular expressions that should match all method names.
  METHOD_SIGNAL_RE = /^[A-Za-z][A-Za-z0-9_]*$/
  # Regular expressions that should match all interface names.
  INTERFACE_ELEMENT_RE = /^[A-Za-z][A-Za-z0-9_]*$/

  # Exception raised when an invalid class definition is encountered.
  class InvalidClassDefinition < Exception
  end

  # = D-Bus interface class
  #
  # This class is the interface descriptor.  In most cases, the Introspect()
  # method call instantiates and configures this class for us.
  #
  # It also is the local definition of interface exported by the program.
  # At the client side, see ProxyObjectInterface
  class Interface
    # @return [String] The name of the interface.
    attr_reader :name
    # @return [Hash{Symbol => DBus::Method}] The methods that are part of the interface.
    attr_reader :methods
    # @return [Hash{Symbol => Signal}] The signals that are part of the interface.
    attr_reader :signals

    # @return [Hash{Symbol => Property}]
    attr_reader :properties

    # Creates a new interface with a given _name_.
    def initialize(name)
      validate_name(name)
      @name = name
      @methods = {}
      @signals = {}
      @properties = {}
    end

    # Validates a service _name_.
    def validate_name(name)
      raise InvalidIntrospectionData if name.bytesize > 255
      raise InvalidIntrospectionData if name =~ /^\./ || name =~ /\.$/
      raise InvalidIntrospectionData if name =~ /\.\./
      raise InvalidIntrospectionData if name !~ /\./
      name.split(".").each do |element|
        raise InvalidIntrospectionData if element !~ INTERFACE_ELEMENT_RE
      end
    end

    # Add _ie_ as a known {Method}, {Signal} or {Property}
    # @param ie [InterfaceElement]
    def define(ie)
      name = ie.name.to_sym
      category = if ie.is_a?(Method)
                   @methods
                 elsif ie.is_a?(Signal)
                   @signals
                 elsif ie.is_a?(Property)
                   @properties
                 end
      category[name] = ie
    end
    alias declare define
    alias << define

    # Defines a method with name _id_ and a given _prototype_ in the
    # interface.
    # Better name: declare_method
    def define_method(id, prototype)
      m = Method.new(id)
      m.from_prototype(prototype)
      define(m)
    end
    alias declare_method define_method
  end # class Interface

  # = A formal parameter has a name and a type
  class FormalParameter
    attr_reader :name
    attr_reader :type

    def initialize(name, type)
      @name = name
      @type = type
    end

    # backward compatibility, deprecated
    def [](index)
      case index
      when 0 then name
      when 1 then type
      end
    end
  end

  # = D-Bus interface element class
  #
  # This is a generic class for entities that are part of the interface
  # such as methods and signals.
  class InterfaceElement
    # The name of the interface element. Symbol
    attr_reader :name
    # The parameters of the interface element. Array: FormalParameter
    attr_reader :params

    # Validates element _name_.
    def validate_name(name)
      return if (name =~ METHOD_SIGNAL_RE) && (name.bytesize <= 255)
      raise InvalidMethodName, name
    end

    # Creates a new element with the given _name_.
    def initialize(name)
      validate_name(name.to_s)
      @name = name
      @params = []
    end

    # Adds a formal parameter with _name_ and _signature_
    # (See also Message#add_param which takes signature+value)
    def add_fparam(name, signature)
      @params << FormalParameter.new(name, signature)
    end

    # Deprecated, for backward compatibility
    def add_param(name_signature_pair)
      add_fparam(*name_signature_pair)
    end
  end # class InterfaceElement

  # = D-Bus interface method class
  #
  # This is a class representing methods that are part of an interface.
  class Method < InterfaceElement
    # The list of return values for the method. Array: FormalParameter
    attr_reader :rets

    # Creates a new method interface element with the given _name_.
    def initialize(name)
      super(name)
      @rets = []
    end

    # Add a return value _name_ and _signature_.
    def add_return(name, signature)
      @rets << FormalParameter.new(name, signature)
    end

    # Add parameter types by parsing the given _prototype_.
    # @param prototype [Prototype]
    def from_prototype(prototype)
      prototype.split(/, */).each do |arg|
        arg = arg.split(" ")
        raise InvalidClassDefinition if arg.size != 2
        dir, arg = arg
        if arg =~ /:/
          arg = arg.split(":")
          name, sig = arg
        else
          sig = arg
        end
        case dir
        when "in"
          add_fparam(name, sig)
        when "out"
          add_return(name, sig)
        end
      end
      self
    end

    # Return an XML string representation of the method interface elment.
    def to_xml
      xml = "    <method name=\"#{@name}\">\n"
      @params.each do |param|
        name = param.name ? "name=\"#{param.name}\" " : ""
        xml += "      <arg #{name}direction=\"in\" type=\"#{param.type}\"/>\n"
      end
      @rets.each do |param|
        name = param.name ? "name=\"#{param.name}\" " : ""
        xml += "      <arg #{name}direction=\"out\" type=\"#{param.type}\"/>\n"
      end
      xml += "    </method>\n"
      xml
    end
  end # class Method

  # = D-Bus interface signal class
  #
  # This is a class representing signals that are part of an interface.
  class Signal < InterfaceElement
    # Add parameter types based on the given _prototype_.
    def from_prototype(prototype)
      prototype.split(/, */).each do |arg|
        if arg =~ /:/
          arg = arg.split(":")
          name, sig = arg
        else
          sig = arg
        end
        add_fparam(name, sig)
      end
      self
    end

    # Return an XML string representation of the signal interface elment.
    def to_xml
      xml = "    <signal name=\"#{@name}\">\n"
      @params.each do |param|
        name = param.name ? "name=\"#{param.name}\" " : ""
        xml += "      <arg #{name}type=\"#{param.type}\"/>\n"
      end
      xml += "    </signal>\n"
      xml
    end
  end # class Signal

  # An (exported) property
  # https://dbus.freedesktop.org/doc/dbus-specification.html#standard-interfaces-properties
  class Property
    # @return [String] The name of the property, for example FooBar.
    attr_reader :name
    attr_reader :type
    # @return [Symbol] :read :write or :readwrite
    attr_reader :access

    # @return [Symbol] What to call at Ruby side. (TODO clarify :foo vs :foo=)
    attr_reader :ruby_name

    def initialize(name, type, access, ruby_name:)
      @name = name
      @type = type
      @access = access
      @ruby_name = ruby_name
    end

    # @return [Boolean]
    def readable?
      access == :read || access == :readwrite
    end

    # @return [Boolean]
    def writable?
      access == :write || access == :readwrite
    end

    # Return introspection XML string representation of the property.
    def to_xml
      "    <property type=\"#{@type}\" name=\"#{@name}\" access=\"#{@access}\"/>\n"
    end
  end
end # module DBus
