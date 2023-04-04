-- | GlobalTestEnvironment shared by tests. We intentionally use an abstract type to
-- wrap up the values we need for tests, with accessors. This way, the
-- tests are less liable to refactorings when we add or change the
-- globalTestEnvironment.
module Harness.GlobalTestEnvironment
  ( GlobalTestEnvironment (..),
    Protocol (..),
    Server (..),
    TestingMode (..),
    PassthroughEnvVars (..),
    serverUrl,
  )
where

import Control.Concurrent.Async (Async)
import Data.Has
import Data.Word
import Database.PostgreSQL.Simple.Options (Options)
import Harness.Logging.Messages
import Harness.PassthroughEnvVars
import Harness.Services.Composed qualified as Services
import Harness.Test.BackendType
import Hasura.Prelude
import Network.WebSockets qualified as WS

-- | static information across an entire test suite run
data GlobalTestEnvironment = GlobalTestEnvironment
  { -- | shared function to log information from tests
    logger :: Logger,
    -- | the mode in which we're running the tests. See 'TestingMode' for
    -- details'.
    testingMode :: TestingMode,
    -- | connection details for the instance of HGE we're connecting to
    server :: Server,
    -- | The protocol with which we make server requests.
    requestProtocol :: Protocol,
    -- | Any environment variable names we wish to pass through to any new HGE
    -- instance
    passthroughEnvVars :: PassthroughEnvVars,
    servicesConfig :: Services.TestServicesConfig
  }

instance Has Logger GlobalTestEnvironment where
  getter = logger
  modifier f x = x {logger = f (logger x)}

instance Has Services.TestServicesConfig GlobalTestEnvironment where
  getter = servicesConfig
  modifier f x = x {servicesConfig = f (servicesConfig x)}

instance Has Services.HgeBinPath GlobalTestEnvironment where
  getter = getter . getter @Services.TestServicesConfig
  modifier f = modifier (modifier @_ @Services.TestServicesConfig f)

instance Has Services.PostgresServerUrl GlobalTestEnvironment where
  getter = getter . getter @Services.TestServicesConfig
  modifier f = modifier (modifier @_ @Services.TestServicesConfig f)

instance Has PassthroughEnvVars GlobalTestEnvironment where
  getter = passthroughEnvVars
  modifier f x = x {passthroughEnvVars = f (passthroughEnvVars x)}

instance Show GlobalTestEnvironment where
  show GlobalTestEnvironment {server} =
    "<GlobalTestEnvironment: " ++ urlPrefix server ++ ":" ++ show (port server) ++ " >"

-- | How should we make requests to `graphql-engine`? Both WebSocket- and HTTP-
-- based requests are supported.
data Protocol = HTTP | WebSocket WS.Connection

-- | Credentials for our testing modes. See 'SpecHook.setupTestingMode' for the
-- practical consequences of this type.
data TestingMode
  = -- | run all tests, unfiltered
    TestEverything
  | -- | run only tests containing this BackendType (or a RemoteSchema, so
    -- those aren't missed)
    TestBackend BackendType
  | -- | run "all the other tests"
    TestNoBackends
  | -- | test a Postgres-compatible using a custom connection string
    TestNewPostgresVariant Options
  deriving (Eq, Ord, Show)

-- | Information about a server that we're working with.
data Server = Server
  { -- | The port to connect on.
    port :: Word16,
    -- | The full URI prefix e.g. http://localhost
    urlPrefix :: String,
    -- | The thread that the server is running on, so we can stop it later.
    thread :: Async ()
  }

instance Show Server where
  show = serverUrl

-- | Extracts the full URL prefix and port number from a given 'Server'.
--
-- @
--   > serverUrl (Server 8080 "http://localhost" someThreadId)
--   "http://localhost:8080"
-- @
serverUrl :: Server -> String
serverUrl Server {urlPrefix, port} = urlPrefix ++ ":" ++ show port