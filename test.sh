#! /bin/bash
PLATFORM=$1
TYPE=$2
COVERAGE=$3
WHERE="cat != ManualTest"
TEST_PATTERN="*Test.dll"
ASSEMBLIES=""
TEST_LOG_FILE="TestLog.txt"

echo "test dir: $TEST_DIR"
if [ -z "$TEST_DIR" ]; then
    TEST_DIR="."
fi

if [ -d "$TEST_DIR/_tests" ]; then
  TEST_DIR="$TEST_DIR/_tests"
fi

COVERAGE_RESULT_DIRECTORY="$TEST_DIR/CoverageResults/"

rm -f "$TEST_LOG_FILE"

# Uncomment to log test output to a file instead of the console
export LIDARR_TESTS_LOG_OUTPUT="File"

NUNIT="$TEST_DIR/NUnit.ConsoleRunner.3.7.0/tools/nunit3-console.exe"
NUNIT_COMMAND="$NUNIT"
NUNIT_PARAMS="--workers=1"

if [ "$PLATFORM" = "Mac" ]; then

  #set up environment
  if [[ -x '/opt/local/bin/mono' ]]; then
      # Macports and mono-supplied installer path
      export PATH="/opt/local/bin:$PATH"
  elif [[ -x '/usr/local/bin/mono' ]]; then
      # Homebrew-supplied path to mono
      export PATH="/usr/local/bin:$PATH"
  fi

  echo $TEST_DIR
  export DYLD_FALLBACK_LIBRARY_PATH="$TEST_DIR"

  if [ -e /Library/Frameworks/Mono.framework ]; then
      MONO_FRAMEWORK_PATH=/Library/Frameworks/Mono.framework/Versions/Current
      export PATH="$MONO_FRAMEWORK_PATH/bin:$PATH"
      export DYLD_FALLBACK_LIBRARY_PATH="$DYLD_FALLBACK_LIBRARY_PATH:$MONO_FRAMEWORK_PATH/lib"
  fi

  if [[ -f '/opt/local/lib/libsqlite3.0.dylib' ]]; then
      export DYLD_FALLBACK_LIBRARY_PATH="$DYLD_FALLBACK_LIBRARY_PATH:/opt/local/lib"
  fi

  export DYLD_FALLBACK_LIBRARY_PATH="$TEST_DIR:/usr/local/lib:/lib:/usr/lib"
  
  #export LD_LIBRARY_PATH="$TEST_DIR:/usr/local/lib:/lib"
  #export DYLD_LIBRARY_PATH="$TEST_DIR:/usr/local/lib:/lib"
  #export DYLD_FALLBACK_LIBRARY_PATH="$TEST_DIR:/usr/local/lib:/lib"

  #echo $LD_LIBRARY_PATH
  #echo $DYLD_LIBRARY_PATH
  echo $DYLD_FALLBACK_LIBRARY_PATH

  # link dylib to user/local/lib directory incase SIP is stopping use of env variables. 
  ln -s $TEST_DIR/*.dylib* /usr/local/lib
  ln -s $TEST_DIR/*.dylib* $TEST_DIR/NUnit.ConsoleRunner.3.7.0/tools/

  sqlite3 -version

  export DYLD_PRINT_LIBRARIES=YES

  #echo $LD_LIBRARY_PATH
  #echo $DYLD_LIBRARY_PATH
  #echo $DYLD_FALLBACK_LIBRARY_PATH
fi

if [ "$PLATFORM" = "Windows" ]; then
  mkdir -p "$ProgramData/Lidarr"
  WHERE="$WHERE && cat != LINUX"
elif [ "$PLATFORM" = "Linux" ] || [ "$PLATFORM" = "Mac" ] ; then
  mkdir -p ~/.config/Lidarr
  WHERE="$WHERE && cat != WINDOWS"
  NUNIT_COMMAND="mono --debug --runtime=v4.0 $NUNIT"
else
  echo "Platform must be provided as first arguement: Windows, Linux or Mac"
  exit 1
fi

if [ "$TYPE" = "Unit" ]; then
  WHERE="$WHERE && cat != IntegrationTest && cat != AutomationTest"
elif [ "$TYPE" = "Integration" ] || [ "$TYPE" = "int" ] ; then
  WHERE="$WHERE && cat == IntegrationTest"
elif [ "$TYPE" = "Automation" ] ; then
  WHERE="$WHERE && cat == AutomationTest"
else
  echo "Type must be provided as second argument: Unit, Integration or Automation"
  exit 2
fi

for i in `find $TEST_DIR -name "$TEST_PATTERN"`;
  do ASSEMBLIES="$ASSEMBLIES $i"
done

if [ "$COVERAGE" = "Coverage" ]; then
  if [ "$PLATFORM" = "Windows" ] || [ "$PLATFORM" = "Linux" ]; then
    dotnet tool install coverlet.console --tool-path="$TEST_DIR/coverlet/"
    mkdir $COVERAGE_RESULT_DIRECTORY
    OPEN_COVER="$TEST_DIR/coverlet/coverlet"
    $OPEN_COVER "$TEST_DIR/" --verbosity "detailed" --format "cobertura" --format "opencover" --output "$COVERAGE_RESULT_DIRECTORY" --exclude "[Lidarr.*.Test]*" --exclude "[Lidarr.Test.*]*" --exclude "[Marr.Data]*" --exclude "[MonoTorrent]*" --exclude "[CurlSharp]*" --target "$NUNIT" --targetargs "$NUNIT_PARAMS --where=\"$WHERE\" $ASSEMBLIES";
    EXIT_CODE=$?
  else
    echo "Coverage only supported on Windows and Linux"
    exit 3
  fi
elif [ "$COVERAGE" = "Test" ] ; then
  $NUNIT_COMMAND --where "$WHERE" $NUNIT_PARAMS $ASSEMBLIES;
  EXIT_CODE=$?
else
  echo "Run Type must be provided as third argument: Coverage or Test"
  exit 3
fi

if [ "$EXIT_CODE" -ge 0 ]; then
  echo "Failed tests: $EXIT_CODE"
  exit 0
else
  exit $EXIT_CODE
fi
