#!/usr/bin/env stack
-- stack --resolver lts-10.4 script --package foundation --package directory --package cryptonite
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DataKinds #-}

import           Data.Char
import           Data.List
import           Data.Either
import           Data.Function (on)
import           Control.Monad (when)
import           System.Directory
import           System.Environment
import           System.Exit
import           System.IO
import           Crypto.Hash (hashWith, SHA256(..), Digest)
import           Config
import           Build
import           Resolver
import           Utils
import           Travis
import           Stack
import qualified Yaml as Y
import qualified Foundation    as F
import qualified Foundation.IO as F

main = do
    let hci = ".haskell-ci"
        -- read and parse .haskell-ci
        readHci = do
            y <- doesFileExist hci
            when (not y) $ quitWith "no .haskell-ci file found"
            parse <$> readFile hci

    a <- getArgs
    case a of
        ["generate"] -> do
            already <- doesFileExist hci
            when already $ quitWith ("this directory already contains a " ++ hci ++ " file")
            writeFile hci $ unlines
                [ "# compiler supported and their equivalent LTS"
                , "compiler: ghc-7.8 lts-2.22"
                , "compiler: ghc-7.10 lts-6.35"
                , "compiler: ghc-8.0 lts-9.21"
                , "compiler: ghc-8.2 lts-10.4"
                , ""
                , "# options"
                , "# option: alias x=y z=v"
                , ""
                , "# builds "
                , "build: ghc-7.8 nohaddock"
                , "build: ghc-8.2"
                , "build: ghc-7.10"
                , "build: ghc-8.0"
                , "build: ghc-8.0 os=osx"
                , ""
                , "# packages"
                , "package: '.'"
                , ""
                , "# extra builds"
                , "hlint: allowed-failure"
                , "weeder: allowed-failure"
                , "coverall: false"
                ]
        ["travis"]      -> do
            cfg <- readHci
            h   <- readHciHash
            putStrLn $ toTravis h cfg
            return ()
        ("stack":name:[]) -> do
            cfg <- readHci
            h   <- readHciHash
            case find (\(BuildEnv b _ _) -> b == name) (builds cfg) of
                Nothing   -> quitWith ("no build name called " ++ name ++ " found")
                Just benv -> do
                    let resolved = resolveBuild cfg benv
                        build    = makeBuildFromEnv cfg resolved
                        gen      = stackYaml build
                    putStrLn $ unlines [ yamlAutoGeneratedComment h, gen ]
        -- ["local-build"] -> do -- try to run all builds locally with every resolver capable on this system
        --    cfg <- readHci
        --    let builds = map (resolveBuilds cfg) $ builds cfg
        _            -> do
            hPutStrLn stderr "usage: haskell-ci [generate|travis|stack <name>]"
            exitFailure
