# frozen_string_literal: true

##
# Module definitions for A2A SDK
#
# This file defines all the necessary module namespaces to prevent
# "uninitialized constant" errors when classes are defined before
# their parent modules.
#

module A2A
  module Types
  end

  module Server
    module Middleware
    end

    module Storage
    end
  end

  module Client
    module Auth
    end

    module Middleware
    end
  end

  module Transport
  end

  module Monitoring
  end

  module Rails
    module Generators
    end
  end

  module Utils
  end

  module Plugins
  end

  module Errors
  end
end