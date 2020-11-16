require 'yaml'
require "sidekiq/extensions/active_record"

module SidekiqBulkJob
  module Utils

    class << self

      def symbolize_keys(obj)
        case obj
        when Array
          obj.inject([]){|res, val|
            res << case val
            when Hash, Array
              symbolize_keys(val)
            else
              val
            end
            res
          }
        when Hash
          obj.inject({}){|res, (key, val)|
            nkey = case key
            when String
              key.to_sym
            else
              key
            end
            nval = case val
            when Hash, Array
              symbolize_keys(val)
            else
              val
            end
            res[nkey] = nval
            res
          }
        else
          obj
        end
      end

      def constantize(camel_cased_word)
        names = camel_cased_word.split("::")

        # Trigger a built-in NameError exception including the ill-formed constant in the message.
        Object.const_get(camel_cased_word) if names.empty?

        # Remove the first blank element in case of '::ClassName' notation.
        names.shift if names.size > 1 && names.first.empty?

        names.inject(Object) do |constant, name|
          if constant == Object
            constant.const_get(name)
          else
            candidate = constant.const_get(name)
            next candidate if constant.const_defined?(name, false)
            next candidate unless Object.const_defined?(name)

            # Go down the ancestors to check if it is owned directly. The check
            # stops when we reach Object or the end of ancestors tree.
            constant = constant.ancestors.inject(constant) do |const, ancestor|
              break const    if ancestor == Object
              break ancestor if ancestor.const_defined?(name, false)
              const
            end

            # owner is in Object, so raise
            constant.const_get(name, false)
          end
        end
      end

      def class_with_method?(klass_name)
        klass_name.include?('.')
      end

      def split_class_name_with_method(klass_name)
        if class_with_method?(klass_name)
          klass_name.split('.')
        else
          [klass_name, :perform]
        end
      end

      def load yaml, legacy_filename = Object.new, filename: nil, fallback: false, symbolize_names: false
        YAML.load yaml, legacy_filename, filename: filename, fallback: fallback, symbolize_names: symbolize_names
      end

      def dump o, io = nil, options = {}
        marshalled = YAML.dump o, io, options
        if marshalled.size > Sidekiq::Extensions::SIZE_LIMIT
          SidekiqBulkJob.logger.warn { "job argument is #{marshalled.bytesize} bytes, you should refactor it to reduce the size" }
        end
        marshalled
      end

    end

  end
end