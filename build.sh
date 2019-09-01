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
artifactsFolderLinux=$artifactsFolder/linux/Lidarr
artifactsFolderMacOS=$artifactsFolder/macos/Lidarr
artifactsFolderMacOSApp=$artifactsFolder/macos-app

nuget='tools/nuget/nuget.exe';
vswhere='tools/vswhere/vswhere.exe';

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
    CheckExitCode dotnet publish $slnFile -c Release --no-self-contained -r win-x64
    CheckExitCode dotnet publish $slnFile -c Release --no-self-contained -r linux-x64
    CheckExitCode dotnet publish $slnFile -c Release --no-self-contained -r osx-x64

    # The tray app is a WindowsDesktop project and wont build on posix
    if [ $os = "windows" ] ; then
        CheckExitCode dotnet publish $winAppProj -c Release --no-self-contained -r win-x64
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

PackageLinux()
{
    ProgressStart 'Creating Linux Package'

    rm -r $artifactsFolderLinux
    mkdir -p $artifactsFolderLinux
    cp -r $outputFolder/linux-x64/publish/* $artifactsFolderLinux
    cp -r $outputFolder/Lidarr.Update/linux-x64/publish $artifactsFolderLinux/Lidarr.Update
    cp -r $outputFolder/UI $artifactsFolderLinux

    CleanFolder $artifactsFolderLinux

    echo "Adding LICENSE.md"
    cp LICENSE.md $artifactsFolderLinux

    echo "Removing Service helpers"
    rm -f $artifactsFolderLinux/ServiceUninstall.*
    rm -f $artifactsFolderLinux/ServiceInstall.*

    echo "Removing native windows binaries Sqlite, fpcalc"
    rm -f $artifactsFolderLinux/fpcalc*

    echo "Removing Lidarr.Windows"
    rm $artifactsFolderLinux/Lidarr.Windows.*

    echo "Adding Lidarr.Mono to UpdatePackage"
    cp $artifactsFolderLinux/Lidarr.Mono.* $artifactsFolderLinux/Lidarr.Update

    ProgressEnd 'Creating Linux Package'
}

PackageMacOS()
{
    ProgressStart 'Creating MacOS Package'

    rm -r $artifactsFolderMacOS
    mkdir -p $artifactsFolderMacOS
    cp -r $outputFolder/osx-x64/publish/* $artifactsFolderMacOS
    cp -r $outputFolder/Lidarr.Update/osx-x64/publish $artifactsFolderMacOS/Lidarr.Update
    cp -r $outputFolder/UI $artifactsFolderMacOS

    CleanFolder $artifactsFolderMacOS

    echo "Adding LICENSE.md"
    cp LICENSE.md $artifactsFolderMacOS

    echo "Adding Startup script"
    cp ./macOS/Lidarr $artifactsFolderMacOS
    dos2unix $artifactsFolderMacOS/Lidarr

    echo "Removing Service helpers"
    rm -f $artifactsFolderMacOS/ServiceUninstall.*
    rm -f $artifactsFolderMacOS/ServiceInstall.*

    echo "Removing native windows fpcalc"
    rm -f $artifactsFolderMacOS/fpcalc.exe

    echo "Removing Lidarr.Windows"
    rm $artifactsFolderMacOS/Lidarr.Windows.*

    echo "Adding Lidarr.Mono to UpdatePackage"
    cp $artifactsFolderMacOS/Lidarr.Mono.* $artifactsFolderMacOS/Lidarr.Update

    ProgressEnd 'Creating MacOS Package'
}

PackageMacOSApp()
{
    ProgressStart 'Creating macOS App Package'

    rm -r $artifactsFolderMacOSApp
    mkdir $artifactsFolderMacOSApp
    cp -r ./macOS/Lidarr.app $artifactsFolderMacOSApp
    mkdir -p $artifactsFolderMacOSApp/Lidarr.app/Contents/MacOS

    echo "Copying Binaries"
    cp -r $artifactsFolderMacOS/* $artifactsFolderMacOSApp/Lidarr.app/Contents/MacOS

    echo "Removing Update Folder"
    rm -r $artifactsFolderMacOSApp/Lidarr.app/Contents/MacOS/Lidarr.Update

    ProgressEnd 'Creating macOS App Package'
}

PackageTests()
{
    ProgressStart 'Creating Test Package'

    cp ./test.sh $testPackageFolder/win-x64/publish
    cp ./test.sh $testPackageFolder/linux-x64/publish
    cp ./test.sh $testPackageFolder/osx-x64/publish
    
    rm -f $testPackageFolder/*.log.config

    # Mac fpcalc being in the linux tests breaks fpcalc detection
    rm $testPackageFolder/linux-x64/publish/fpcalc

    # geckodriver.exe isn't copied by dotnet publish
    cp $testPackageFolder/geckodriver.exe $testPackageFolder/win-x64/publish

    CleanFolder $testPackageFolder

    ProgressEnd 'Creating Test Package'
}

PackageWindows()
{
    ProgressStart 'Creating Windows Package'

    rm -r $artifactsFolderWindows
    mkdir -p $artifactsFolderWindows
    cp -r $outputFolder/win-x64/publish/* $artifactsFolderWindows
    cp -r $outputFolder/Lidarr.Update/win-x64/publish $artifactsFolderWindows/Lidarr.Update
    cp -r $outputFolder/UI $artifactsFolderWindows

    CleanFolder $artifactsFolderWindows
        
    echo "Adding LICENSE.md"
    cp LICENSE.md $artifactsFolderWindows

    echo "Removing Lidarr.Mono"
    rm -f $artifactsFolderWindows/Lidarr.Mono.*

    echo "Adding Lidarr.Windows to UpdatePackage"
    cp $artifactsFolderWindows/Lidarr.Windows.* $artifactsFolderWindows/Lidarr.Update

    echo "Removing MacOS fpcalc"
    rm $artifactsFolderWindows/fpcalc

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
    PackageLinux
    PackageMacOS
    PackageMacOSApp
fi
