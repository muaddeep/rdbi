module RDBI
    module Driver
        class Mock
            attr_reader :connect_args

            def initialize(*args)
                @connect_args = args
            end

            def new_handle 
                return DBH.new(*@connect_args)
            end
        end

        class Mock::DBH < RDBI::Database
            extend MethLab

            attr_accessor :next_action

            def ping
                10
            end

            inline(:rollback) { super; "rollback called" }

            # XXX more methods to be defined this way.
            inline(:commit) do |*args|
                super

                ret = nil

                if next_action
                    ret = next_action.call(*args)
                    self.next_action = nil
                end

                ret
            end
        end
    end
end

# vim: syntax=ruby ts=4 et sw=4 sts=4