module Travis where

import           Config
import           Build
import           Utils
import           Stack
import qualified Yaml as Y

toTravis :: Digest SHA256 -> C -> String
toTravis hash c = unlines $
    [ yamlAutoGeneratedComment hash
    , ""
    , "# Use new container infrastructure to enable caching"
    , "sudo: false"
    , ""
    , "# Caching so the next build will be fast too."
    , "cache:"
    , "  directories:"
    , "  - $HOME/.ghc"
    , "  - $HOME/.stack"
    , "  - $HOME/.local"
    , ""
    , "matrix:"
    , "  include:"
    ] ++ envs ++
    [ "  allow_failures:"
    ] ++ failureEnvs ++
    [ ""
    , "install:"
    , "  - export PATH=$HOME/.local/bin::$HOME/.cabal/bin:$PATH"
    , "  - mkdir -p ~/.local/bin"
    , "  - |"
    , "    case \"$BUILD\" in"
    , "      stack|weeder)"
    , "        if [ `uname` = \"Darwin\" ]"
    , "        then"
    , "          travis_retry curl --insecure -L https://www.stackage.org/stack/osx-x86_64 | tar xz --strip-components=1 --include '*/stack' -C ~/.local/bin"
    , "        else"
    , "          travis_retry curl -L https://www.stackage.org/stack/linux-x86_64 | tar xz --wildcards --strip-components=1 -C ~/.local/bin '*/stack'"
    , "        fi"
    , "      ;;"
    , "    cabal)"
    , "      ;;"
    , "    esac"
    , ""
    , "script:"
    , "- |"
    , "  set -ex"
    , "  if [ \"x${RUNTEST}\" = \"xfalse\" ]; then exit 0; fi"
    , "  case \"$BUILD\" in"
    , "    stack)"
    , "      # create the build stack.yaml"
    , "      case \"$RESOLVER\" in"
    ] ++ scriptResolverCase ++
    [ "      esac"
    , "      # build & run test"
    , "      stack --no-terminal test --install-ghc --coverage --bench --no-run-benchmarks ${HADDOCK_OPTS}"
    , "      ;;"
    , "    hlint)"
    , "      curl -sL https://raw.github.com/ndmitchell/hlint/master/misc/travis.sh | sh -s . --cpp-define=__GLASGOW_HASKELL__=800 --cpp-define=x86_64_HOST_ARCH=1 --cpp-define=mingw32_HOST_OS=1"
    , "      ;;"
    , "    weeder)"
    , "      stack --no-terminal build --install-ghc"
    , "      curl -sL https://raw.github.com/ndmitchell/weeder/master/misc/travis.sh | sh -s ."
    , "      ;;"
    , "  esac"
    , "  set +ex"
    ]
  where
    -- resolved build
    bs = map (resolveBuild c) $ builds c

    optionalBuilds =
        [ BuildHLint, BuildWeeder ]

    scriptResolverCase = concatMap matchLines $ map (makeBuildFromEnv c) $ bs
      where
        matchLines build =
            [ "      " ++ buildName build ++ ")"
            , "        echo \"" ++ escapeQuote (stackYaml build) ++ "\" > stack.yaml"
            , "        export HADDOCK_OPTs=\"" ++ haddockOpt ++ "\""
            , "        ;;"
            ]
         where haddockOpt | buildUseHaddock build = "--haddock --no-haddock-deps"
                          | otherwise             = "--no-haddock"

    envs = concatMap env (map toBuildTypes bs ++ optionalBuilds)
    failureEnvs = concatMap env (map toBuildTypes (filter isAllowedFailure bs) ++ optionalBuilds)
      where isAllowedFailure (BuildEnv _ simples _) = "allowed-failure" `elem` simples

    toBuildTypes (BuildEnv r simples kvs) =
        BuildStack r (maybe Linux (\os -> if os == "osx" then OsX else Linux) $ lookup "os" kvs)

    env BuildHLint =
        [ (++) "  - " $ Y.toString $ Y.dict
            [ (Y.key "env", Y.string "BUILD=hlint"), (Y.key "compiler", Y.string "hlint"), language ] ]
    env BuildWeeder =
        [ (++) "  - " $ Y.toString $ Y.dict
            [ (Y.key "env", Y.string "BUILD=weeder"), (Y.key "compiler", Y.string "weeder"), language, addOn ] ]
    env (BuildStack compiler ostype) =
        [ (++) "  - " $ Y.toString $ Y.dict $
            [ (Y.key "env", Y.string ("BUILD=stack RESOLVER=" ++ compiler))
            , (Y.key "compiler", Y.string compiler), language, addOn
            ] ++ (if ostype == OsX then [ (Y.key "os", Y.string "osx") ] else [])
        ]
    addOn = (Y.key "addons", Y.dict [ (Y.key "apt", Y.dict [ (Y.key "packages", pkgs) ]) ] )
      where pkgs = Y.list $ map Y.string (["libgmp-dev"] ++ travisAptAddOn c)
    language = (Y.key "language", Y.string "generic")

