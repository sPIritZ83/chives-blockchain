#!/bin/bash

if [ ! "$1" ]; then
  echo "This script requires either amd64 of arm64 as an argument"
	exit 1
elif [ "$1" = "amd64" ]; then
	PLATFORM="$1"
	DIR_NAME="chives-blockchain-linux-x64"
else
	PLATFORM="$1"
	DIR_NAME="chives-blockchain-linux-arm64"
fi

pip install setuptools_scm
pip install requests
# The environment variable CHIVES_INSTALLER_VERSION needs to be defined
# If the env variable NOTARIZE and the username and password variables are
# set, this will attempt to Notarize the signed DMG
CHIVES_INSTALLER_VERSION=$(python installer-version.py)

if [ ! "$CHIVES_INSTALLER_VERSION" ]; then
	echo "WARNING: No environment variable CHIVES_INSTALLER_VERSION set. Using 0.0.0."
	CHIVES_INSTALLER_VERSION="0.0.0"
fi
echo "Chives Installer Version is: $CHIVES_INSTALLER_VERSION"

echo "Installing npm and electron packagers"
sudo npm install electron-packager -g
sudo npm install electron-installer-debian -g

echo "Create dist/"
rm -rf dist
mkdir dist

echo "Create executables with pyinstaller"
pip install pyinstaller==4.5
SPEC_FILE=$(python -c 'import chives; print(chives.PYINSTALLER_SPEC_PATH)')
pyinstaller --log-level=INFO "$SPEC_FILE"
LAST_EXIT_CODE=$?
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "pyinstaller failed!"
	exit $LAST_EXIT_CODE
fi

cp -r dist/daemon ../chives-blockchain-gui
cd .. || exit
cd chives-blockchain-gui || exit

echo "npm build"
npm install
npm audit fix
npm run build
LAST_EXIT_CODE=$?
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "npm run build failed!"
	exit $LAST_EXIT_CODE
fi

# sets the version for chives-blockchain in package.json
cp package.json package.json.orig
jq --arg VER "$CHIVES_INSTALLER_VERSION" '.version=$VER' package.json > temp.json && mv temp.json package.json

electron-packager . chives-blockchain --asar.unpack="**/daemon/**" --platform=linux \
--icon=src/assets/img/Chives.icns --overwrite --app-bundle-id=net.chives.blockchain \
--appVersion=$CHIVES_INSTALLER_VERSION
LAST_EXIT_CODE=$?

# reset the package.json to the original
mv package.json.orig package.json

if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "electron-packager failed!"
	exit $LAST_EXIT_CODE
fi

mv $DIR_NAME ../build_scripts/dist/
cd ../build_scripts || exit

echo "Create chives-$CHIVES_INSTALLER_VERSION.deb"
rm -rf final_installer
mkdir final_installer
electron-installer-debian --src dist/$DIR_NAME/ --dest final_installer/ \
--arch "$PLATFORM" --options.version $CHIVES_INSTALLER_VERSION
LAST_EXIT_CODE=$?
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "electron-installer-debian failed!"
	exit $LAST_EXIT_CODE
fi

ls final_installer/
