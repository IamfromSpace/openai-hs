{-# LANGUAGE CPP #-}
{-# OPTIONS_GHC -cpp -pgmPcpphs -optP--cpp #-}

module OpenAI.Client
  ( -- * Basics
    ApiKey,
    OpenAIClient,
    makeOpenAIClient,
    ClientError (..),

    -- * Helper types
    TimeStamp (..),
    OpenAIList (..),

    -- * Engine
    EngineId (..),
    Engine (..),
    listEngines,
    getEngine,

    -- * Text completion
    TextCompletionId (..),
    TextCompletionChoice (..),
    TextCompletion (..),
    TextCompletionCreate (..),
    defaultTextCompletionCreate,
    completeText,

    -- * Embeddings
    EmbeddingCreate (..),
    Embedding (..),
    createEmbedding,

    -- * Fine tunes
    FineTuneId (..),
    FineTuneCreate (..),
    defaultFineTuneCreate,
    FineTune (..),
    FineTuneEvent (..),
    createFineTune,
    listFineTunes,
    getFineTune,
    cancelFineTune,
    listFineTuneEvents,

    -- * Searching
    SearchResult (..),
    SearchResultCreate (..),
    searchDocuments,

    -- * File API
    FileCreate (..),
    File (..),
    FileId (..),
    FileHunk (..),
    SearchHunk (..),
    ClassificationHunk (..),
    FineTuneHunk (..),
    FileDeleteConfirmation (..),
    createFile,
    deleteFile,

    -- * Answer API
    getAnswer,
    AnswerReq (..),
    AnswerResp (..),

    -- *
    ChatCompletionMessage (..),
    ChatCompletionCreate (..),
    ChatCompletionId (..),
    ChatCompletionChoice (..),
    ChatCompletionUsage (..),
    ChatCompletion (..),
    defaultChatCompletionCreate,
    completeChat
  )
where

import qualified Data.ByteString.Lazy as BSL
import Data.Proxy
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import Network.HTTP.Client (Manager)
import OpenAI.Api
import OpenAI.Client.Internal.Helpers
import OpenAI.Resources
import Servant.API
import Servant.Client
import qualified Servant.Multipart.Client as MP

-- | Your OpenAI API key. Can be obtained from the OpenAI dashboard. Format: @sk-<redacted>@
type ApiKey = T.Text

-- | Holds a 'Manager' and your API key.
data OpenAIClient = OpenAIClient
  -- basic auth is deprecated
  { scBasicAuthData :: BasicAuthData,
    scApiKey :: T.Text,
    scManager :: Manager,
    scMaxRetries :: Int
  }

-- | Construct a 'OpenAIClient'. Note that the passed 'Manager' must support https (e.g. via @http-client-tls@)
makeOpenAIClient ::
  ApiKey ->
  Manager ->
  -- | Number of automatic retries the library should attempt.
  Int ->
  OpenAIClient
makeOpenAIClient k = OpenAIClient (BasicAuthData "" (T.encodeUtf8 k)) k

api :: Proxy OpenAIApi
api = Proxy

openaiBaseUrl :: BaseUrl
openaiBaseUrl = BaseUrl Https "api.openai.com" 443 ""

#define EP0(N, R) \
    N##' :: BasicAuthData -> ClientM R;\
    N :: OpenAIClient -> IO (Either ClientError R);\
    N sc = runRequest (scMaxRetries sc) 0 $ runClientM (N##' (scBasicAuthData sc)) (mkClientEnv (scManager sc) openaiBaseUrl)

#define EP(N, ARG, R) \
    N##' :: BasicAuthData -> ARG -> ClientM R;\
    N :: OpenAIClient -> ARG -> IO (Either ClientError R);\
    N sc a = runRequest (scMaxRetries sc) 0 $ runClientM (N##' (scBasicAuthData sc) a) (mkClientEnv (scManager sc) openaiBaseUrl)

#define EP2(N, ARG, ARG2, R) \
    N##' :: BasicAuthData -> ARG -> ARG2 -> ClientM R;\
    N :: OpenAIClient -> ARG -> ARG2 -> IO (Either ClientError R);\
    N sc a b = runRequest (scMaxRetries sc) 0 $ runClientM (N##' (scBasicAuthData sc) a b) (mkClientEnv (scManager sc) openaiBaseUrl)

#define EP2V1(N, ARG, ARG2, R) \
    N##' :: ARG -> ARG2 -> ClientM R;\
    N :: OpenAIClient -> ARG2 -> IO (Either ClientError R);\
    N sc a = runRequest (scMaxRetries sc) 0 $ runClientM (N##' (Just ("Bearer " <> scApiKey sc)) a) (mkClientEnv (scManager sc) openaiBaseUrl)

EP2 (completeText, EngineId, TextCompletionCreate, TextCompletion)
EP2 (searchDocuments, EngineId, SearchResultCreate, (OpenAIList SearchResult))
EP2 (createEmbedding, EngineId, EmbeddingCreate, (OpenAIList Embedding))
EP2V1 (completeChat, Maybe ApiKey, ChatCompletionCreate, ChatCompletion)

EP (createFineTune, FineTuneCreate, FineTune)
EP0 (listFineTunes, (OpenAIList FineTune))
EP (getFineTune, FineTuneId, FineTune)
EP (cancelFineTune, FineTuneId, FineTune)
EP (listFineTuneEvents, FineTuneId, (OpenAIList FineTuneEvent))

EP0 (listEngines, (OpenAIList Engine))
EP (getEngine, EngineId, Engine)

createFile :: OpenAIClient -> FileCreate -> IO (Either ClientError File)
createFile sc rfc =
  do
    bnd <- MP.genBoundary
    createFileInternal sc (bnd, rfc)

EP (createFileInternal, (BSL.ByteString, FileCreate), File)
EP (deleteFile, FileId, FileDeleteConfirmation)

EP (getAnswer, AnswerReq, AnswerResp)

( listEngines'
    :<|> getEngine'
    :<|> completeText'
    :<|> searchDocuments'
    :<|> createEmbedding'
  )
  :<|> (createFileInternal' :<|> deleteFile')
  :<|> getAnswer'
  :<|> ( createFineTune'
           :<|> listFineTunes'
           :<|> getFineTune'
           :<|> cancelFineTune'
           :<|> listFineTuneEvents'
       )
  :<|> completeChat'
         =
    client api
