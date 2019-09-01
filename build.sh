#! /bin/bash
msBuildVersion='15.0'
outputFolder='./_output'
testPackageFolder='./_tests/'
sourceFolder='./src'
slnFile=$sourceFolder/Lidarr.sln
winAppProj=$sourceFolder/NzbDrone/Lidarr.csproj

#Artifact variables
artifactsFolder="./_artifacts";
artifactsFolderWindows=$artifactsFolder/windows/Lidarr
artifactsFolderLinux=$artifactsFolder/linux
artifactsFolderMacOS=$artifactsFolder/macos/Lidarr
artifactsFolderMacOSApp=$artifactsFolder/macos-app

CheckExitCode()
{
    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        echo "error with $1" >&2
        exit 1
    fi
    return $status
}

ProgressStart()
{
    echo "Start '$1'"
}

ProgressEnd()
{
    echo "Finish '$1'"
}

UpdateVersionNumber()
{
    if [ "$LIDARRVERSION" != "" ]; then
        echo "Updating Version Info"
        sed -i "s/<AssemblyVersion>[0-9.*]\+<\/AssemblyVersion>/<AssemblyVersion>$LIDARRVERSION<\/AssemblyVersion>/g" ./src/Directory.Build.props
        sed -i "s/<AssemblyConfiguration>[\$()A-Za-z-]\+<\/AssemblyConfiguration>/<AssemblyConfiguration>${BUILD_SOURCEBRANCHNAME}<\/AssemblyConfiguration>/g" ./src/Directory.Build.props
    fi
}

CleanFolder()
{
    local path=$1

    find $path -name "*.transform" -exec rm "{}" \;

    echo "Removing FluentValidation.Resources files"
    find $path -name "FluentValidation.resources.dll" -exec rm "{}" \;
    find $path -name "App.config" -exec rm "{}" \;

    echo "Removing vshost files"
    find $path -name "*.vshost.exe" -exec rm "{}" \;

    echo "Removing Empty folders"
    find $path -depth -empty -type d -exec rm -r "{}" \;
}

LintUI()
{
    ProgressStart 'ESLint'
    CheckExitCode yarn eslint
    ProgressEnd 'ESLint'

    ProgressStart 'Stylelint'
    if [ $os = "windows" ] ; then
        CheckExitCode yarn stylelint-windows
    else
        CheckExitCode yarn stylelint-linux
    fi
    ProgressEnd 'Stylelint'
}

Build()
{
    ProgressStart 'Build'

    rm -rf $outputFolder
    rm -rf $testPackageFolder

    CheckExitCode dotnet clean $slnFile -c Debug
    CheckExitCode dotnet clean $slnFile -c Release
    CheckExitCode dotnet build $slnFile -c Release
    CheckExitCode dotnet publish $slnFile -c Release -f netcoreapp3.0 -r win-x64
    CheckExitCode dotnet publish $slnFile -c Release -f netcoreapp3.0 -r osx-x64
    CheckExitCode dotnet publish $slnFile -c Release -f netcoreapp3.0 -r linux-x64
    CheckExitCode dotnet publish $slnFile -c Release -f net462 -r linux-x64

    # The tray app is a WindowsDesktop project and wont build on posix
    if [ $os = "windows" ] ; then
        CheckExitCode dotnet publish $winAppProj -c Release -f netcoreapp3.0 -r win-x64
    fi

    ProgressEnd 'Build'
}

RunGulp()
{
    ProgressStart 'yarn install'
    yarn install
    ProgressEnd 'yarn install'

    LintUI

    ProgressStart 'Running gulp'
    CheckExitCode yarn run build --production
    ProgressEnd 'Running gulp'
}

PackageFiles()
{
    local folder="$1"
    local framework="$2"
    local runtime="$3"

    rm -r $folder
    mkdir -p $folder
    cp -r $outputFolder/$framework/$runtime/publish/* $folder
    cp -r $outputFolder/Lidarr.Update/$framework/$runtime/publish $folder/Lidarr.Update
    cp -r $outputFolder/UI $folder

    CleanFolder $folder

    echo "Adding LICENSE.md"
    cp LICENSE.md $folder
}

PackageLinux()
{
    local framework="$1"

    ProgressStart "Creating Linux Package for $framework"

    local runtime="linux-x64"
    local folder=$artifactsFolderLinux/$1/Lidarr

    PackageFiles "$folder" $framework $runtime

    echo "Removing Service helpers"
    rm -f $folder/ServiceUninstall.*
    rm -f $folder/ServiceInstall.*

    echo "Removing native windows binaries Sqlite, fpcalc"
    rm -f $folder/fpcalc*

    echo "Removing Lidarr.Windows"
    rm $folder/Lidarr.Windows.*

    echo "Adding Lidarr.Mono to UpdatePackage"
    cp $folder/Lidarr.Mono.* $folder/Lidarr.Update

    ProgressEnd "Creating Linux Package for $framework"
}

PackageMacOS()
{
    ProgressStart 'Creating MacOS Package'

    local folder=$artifactsFolderMacOS

    PackageFiles "$folder" "netcoreapp3.0" "osx-x64"

    echo "Adding Startup script"
    cp ./macOS/Lidarr $folder
    dos2unix $folder/Lidarr

    echo "Removing Service helpers"
    rm -f $folder/ServiceUninstall.*
    rm -f $folder/ServiceInstall.*

    echo "Removing native windows fpcalc"
    rm -f $folder/fpcalc.exe

    echo "Removing Lidarr.Windows"
    rm $folder/Lidarr.Windows.*

    echo "Adding Lidarr.Mono to UpdatePackage"
    cp $folder/Lidarr.Mono.* $artifactsFolderMacOS/Lidarr.Update

    ProgressEnd 'Creating MacOS Package'
}

PackageMacOSApp()
{
    ProgressStart 'Creating macOS App Package'

    local folder=$artifactsFolderMacOSApp

    rm -r $folder
    mkdir $folder
    cp -r ./macOS/Lidarr.app $folder
    mkdir -p $folder/Lidarr.app/Contents/MacOS

    echo "Copying Binaries"
    cp -r $artifactsFolderMacOS/* $folder/Lidarr.app/Contents/MacOS

    echo "Removing Update Folder"
    rm -r $folder/Lidarr.app/Contents/MacOS/Lidarr.Update

    ProgressEnd 'Creating macOS App Package'
}

PackageTests()
{
    ProgressStart 'Creating Test Package'

    cp ./test.sh $testPackageFolder/netcoreapp3.0/win-x64/publish
    cp ./test.sh $testPackageFolder/netcoreapp3.0/linux-x64/publish
    cp ./test.sh $testPackageFolder/net462/linux-x64/publish
    cp ./test.sh $testPackageFolder/netcoreapp3.0/osx-x64/publish
    
    rm -f $testPackageFolder/*.log.config

    # Mac fpcalc being in the linux tests breaks fpcalc detection
    rm $testPackageFolder/netcoreapp3.0/linux-x64/publish/fpcalc
    rm $testPackageFolder/net462/linux-x64/publish/fpcalc

    # geckodriver.exe isn't copied by dotnet publish
    cp $testPackageFolder/netcoreapp3.0/geckodriver.exe $testPackageFolder/netcoreapp3.0/win-x64/publish

    CleanFolder $testPackageFolder

    ProgressEnd 'Creating Test Package'
}

PackageWindows()
{
    ProgressStart 'Creating Windows Package'

    local runtime="win-x64"
    local folder=$artifactsFolderWindows/$1
    
    PackageFiles "$folder" "netcoreapp3.0" "win-x64"

    echo "Removing Lidarr.Mono"
    rm -f $folder/Lidarr.Mono.*

    echo "Adding Lidarr.Windows to UpdatePackage"
    cp $folder/Lidarr.Windows.* $folder/Lidarr.Update

    echo "Removing MacOS fpcalc"
    rm $folder/fpcalc

    ProgressEnd 'Creating Windows Package'
}

# Use mono or .net depending on OS
case "$(uname -s)" in
    CYGWIN*|MINGW32*|MINGW64*|MSYS*)
        # on windows, use dotnet
        os="windows"
        ;;
    *)
        # otherwise use mono
        os="posix"
        ;;
esac

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    --only-backend)
        ONLY_BACKEND=YES
        shift # past argument
        ;;
    --only-frontend)
        ONLY_FRONTEND=YES
        shift # past argument
        ;;
    --only-packages)
        ONLY_PACKAGES=YES
        shift # past argument
        ;;
    *)    # unknown option
        POSITIONAL+=("$1") # save it in an array for later
        shift # past argument
        ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

# Only build backend if we haven't set only-frontend or only-packages
if [ -z "$ONLY_FRONTEND" ] && [ -z "$ONLY_PACKAGES" ];
then
    UpdateVersionNumber
    Build
    PackageTests
fi

# Only build frontend if we haven't set only-backend or only-packages
if [ -z "$ONLY_BACKEND" ] && [ -z "$ONLY_PACKAGES" ];
then
   RunGulp
fi

# Only package if we haven't set only-backend or only-frontend
if [ -z "$ONLY_BACKEND" ] && [ -z "$ONLY_FRONTEND" ];
then
    PackageWindows
    PackageLinux "netcoreapp3.0"
    PackageLinux "net462"
    PackageMacOS
    PackageMacOSApp
fi
