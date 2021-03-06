RELEASE_TIMESTAMP=`date +%Y-%m-%d`

RELEASE_INC_VERSION=`cat Updates/build_version.txt`
RELEASE_INC_VERSION=$((RELEASE_INC_VERSION+1))

if [ "x$1" == "x" ]; then
	RELEASE_TYPE="canary"
	echo "No release type specified, using ${RELEASE_TYPE}"
else
	RELEASE_TYPE=$1
fi

RELEASE_VERSION="2.0.1.${RELEASE_INC_VERSION}"
RELEASE_NAME="${RELEASE_VERSION}_${RELEASE_TYPE}_${RELEASE_TIMESTAMP}"

RELEASE_CHANGELOG_FILE="changelog.txt"
RELEASE_CHANGELOG_NEWS_FILE="changelog-news.txt"

RELEASE_FILE_NAME="duplicati-${RELEASE_NAME}"

GIT_STASH_NAME="auto-build-${RELEASE_TIMESTAMP}"

UPDATE_ZIP_URLS="http://updates.duplicati.com/${RELEASE_TYPE}/${RELEASE_FILE_NAME}.zip;http://alt.updates.duplicati.com/${RELEASE_TYPE}/${RELEASE_FILE_NAME}.zip"
UPDATE_MANIFEST_URLS="http://updates.duplicati.com/${RELEASE_TYPE}/latest.manifest;http://alt.updates.duplicati.com/${RELEASE_TYPE}/latest.manifest"
UPDATER_KEYFILE="${HOME}/Dropbox/Privat/Duplicati-updater-release.key"
GPG_KEYFILE="${HOME}/Dropbox/Privat/Duplicati-updater-gpgkey.key"
GITHUB_TOKEN_FILE="${HOME}/.config/github-api-token"
XBUILD=/Library/Frameworks/Mono.framework/Commands/xbuild
GPG=/usr/local/bin/gpg2

if [ "${RELEASE_TYPE}" == "nightly" ]; then
	OTHER_UPLOADS=""
elif [ "${RELEASE_TYPE}" == "canary" ]; then
	OTHER_UPLOADS="nightly"
elif [ "${RELEASE_TYPE}" == "experimental" ]; then
	OTHER_UPLOADS="nightly canary"
elif [ "${RELEASE_TYPE}" == "beta" ]; then
	OTHER_UPLOADS="experimental canary nightly"
elif [ "${RELEASE_TYPE}" == "stable" ]; then
	OTHER_UPLOADS="beta experimental canary nightly"
else
	echo "Unsupported release type: ${RELEASE_TYPE}, supported types are: nightly, canary, experimental, beta, stable"
	exit 0
fi


if [ ! -f "${RELEASE_CHANGELOG_FILE}" ]; then
	echo "Changelog file is missing..."
	exit 0
fi

if [ ! -f "${RELEASE_CHANGELOG_NEWS_FILE}" ]; then
	echo "No updates to changelog file found"
	echo
	echo "To make a build without changelog news, run:"
	echo "    touch ""${RELEASE_CHANGELOG_NEWS_FILE}"" "
	exit 0
fi

echo -n "Enter keyfile password: "
read -s KEYFILE_PASSWORD
echo

RELEASE_CHANGEINFO_NEWS=`cat "${RELEASE_CHANGELOG_NEWS_FILE}"`

git stash save "${GIT_STASH_NAME}"

if [ ! "x${RELEASE_CHANGEINFO_NEWS}" == "x" ]; then

	echo "${RELEASE_TIMESTAMP}" > "tmp_changelog.txt"
	echo "==========" >> "tmp_changelog.txt"
	echo "${RELEASE_CHANGEINFO_NEWS}" >> "tmp_changelog.txt"
	echo >> "tmp_changelog.txt"
	cat "${RELEASE_CHANGELOG_FILE}" >> "tmp_changelog.txt"
	cp "tmp_changelog.txt" "${RELEASE_CHANGELOG_FILE}"
	rm "tmp_changelog.txt"
fi

echo "${RELEASE_NAME}" > "Duplicati/License/VersionTag.txt"
echo "${RELEASE_TYPE}" > "Duplicati/Library/AutoUpdater/AutoUpdateBuildChannel.txt"
echo "${UPDATE_MANIFEST_URLS}" > "Duplicati/Library/AutoUpdater/AutoUpdateURL.txt"
cp "Updates/release_key.txt"  "Duplicati/Library/AutoUpdater/AutoUpdateSignKey.txt"

RELEASE_CHANGEINFO=`cat ${RELEASE_CHANGELOG_FILE}`
if [ "x${RELEASE_CHANGEINFO}" == "x" ]; then
    echo "No information in changeinfo file"
    exit 0
fi

rm -rf "Duplicati/GUI/Duplicati.GUI.TrayIcon/bin/Release"

mono "BuildTools/UpdateVersionStamp/bin/Debug/UpdateVersionStamp.exe" --version="${RELEASE_VERSION}"
${XBUILD} /p:Configuration=Debug "BuildTools/AutoUpdateBuilder/AutoUpdateBuilder.sln"

${XBUILD} /p:Configuration=Release Duplicati.sln
BUILD_STATUS=$?

if [ "${BUILD_STATUS}" -ne 0 ]; then
    echo "Failed to build, xbuild gave ${BUILD_STATUS}, exiting"
    exit 4
fi

if [ ! -d "Updates/build" ]; then mkdir "Updates/build"; fi

UPDATE_SOURCE=Updates/build/${RELEASE_TYPE}_source-${RELEASE_VERSION}
UPDATE_TARGET=Updates/build/${RELEASE_TYPE}_target-${RELEASE_VERSION}

if [ -e "${UPDATE_SOURCE}" ]; then rm -rf "${UPDATE_SOURCE}"; fi
if [ -e "${UPDATE_TARGET}" ]; then rm -rf "${UPDATE_TARGET}"; fi

mkdir "${UPDATE_SOURCE}"
mkdir "${UPDATE_TARGET}"

cp -R Duplicati/GUI/Duplicati.GUI.TrayIcon/bin/Release/* "${UPDATE_SOURCE}"
cp -R Duplicati/Server/webroot "${UPDATE_SOURCE}"

if [ -e "${UPDATE_SOURCE}/control_dir" ]; then rm -rf "${UPDATE_SOURCE}/control_dir"; fi
if [ -e "${UPDATE_SOURCE}/Duplicati-server.sqlite" ]; then rm "${UPDATE_SOURCE}/Duplicati-server.sqlite"; fi
if [ -e "${UPDATE_SOURCE}/Duplicati.debug.log" ]; then rm "${UPDATE_SOURCE}/Duplicati.debug.log"; fi
if [ -e "${UPDATE_SOURCE}/updates" ]; then rm -rf "${UPDATE_SOURCE}/updates"; fi
rm -rf "${UPDATE_SOURCE}/"*.mdb;
rm -rf "${UPDATE_SOURCE}/"*.pdb;

echo
echo "Building signed package ..."

mono BuildTools/AutoUpdateBuilder/bin/Debug/AutoUpdateBuilder.exe --input="${UPDATE_SOURCE}" --output="${UPDATE_TARGET}" --keyfile="${UPDATER_KEYFILE}" --manifest=Updates/${RELEASE_TYPE}.manifest --changeinfo="${RELEASE_CHANGEINFO}" --displayname="${RELEASE_NAME}" --remoteurls="${UPDATE_ZIP_URLS}" --version="${RELEASE_VERSION}" --keyfile-password="${KEYFILE_PASSWORD}" --gpgkeyfile="${GPG_KEYFILE}" --gpgpath="${GPG}"

if [ ! -f "${UPDATE_TARGET}/package.zip" ]; then
	mono BuildTools/UpdateVersionStamp/bin/Debug/UpdateVersionStamp.exe --version="2.0.0.7"	
	
	echo "Something went wrong while building the package, no output found"
	exit 5
fi

echo "${RELEASE_INC_VERSION}" > "Updates/build_version.txt"

mv "${UPDATE_TARGET}/package.zip" "${UPDATE_TARGET}/latest.zip"
mv "${UPDATE_TARGET}/autoupdate.manifest" "${UPDATE_TARGET}/latest.manifest"
mv "${UPDATE_TARGET}/package.zip.sig" "${UPDATE_TARGET}/latest.zip.sig"
mv "${UPDATE_TARGET}/package.zip.sig.asc" "${UPDATE_TARGET}/latest.zip.sig.asc"
cp "${UPDATE_TARGET}/latest.zip" "${UPDATE_TARGET}/${RELEASE_FILE_NAME}.zip"
cp "${UPDATE_TARGET}/latest.manifest" "${UPDATE_TARGET}/${RELEASE_FILE_NAME}.manifest"
cp "${UPDATE_TARGET}/latest.zip.sig" "${UPDATE_TARGET}/${RELEASE_FILE_NAME}.zip.sig"
cp "${UPDATE_TARGET}/latest.zip.sig.asc" "${UPDATE_TARGET}/${RELEASE_FILE_NAME}.zip.sig.asc"

mono BuildTools/UpdateVersionStamp/bin/Debug/UpdateVersionStamp.exe --version="2.0.0.7"

echo "Uploading binaries"
aws --profile=duplicati-upload s3 cp "${UPDATE_TARGET}/${RELEASE_FILE_NAME}.zip" "s3://updates.duplicati.com/${RELEASE_TYPE}/${RELEASE_FILE_NAME}.zip"
aws --profile=duplicati-upload s3 cp "${UPDATE_TARGET}/${RELEASE_FILE_NAME}.zip.sig" "s3://updates.duplicati.com/${RELEASE_TYPE}/${RELEASE_FILE_NAME}.zip.sig"
aws --profile=duplicati-upload s3 cp "${UPDATE_TARGET}/${RELEASE_FILE_NAME}.zip.sig.asc" "s3://updates.duplicati.com/${RELEASE_TYPE}/${RELEASE_FILE_NAME}.zip.sig.asc"
aws --profile=duplicati-upload s3 cp "${UPDATE_TARGET}/${RELEASE_FILE_NAME}.manifest" "s3://updates.duplicati.com/${RELEASE_TYPE}/${RELEASE_FILE_NAME}.manifest"

aws --profile=duplicati-upload s3 cp "s3://updates.duplicati.com/${RELEASE_TYPE}/${RELEASE_FILE_NAME}.manifest" "s3://updates.duplicati.com/${RELEASE_TYPE}/latest.manifest"

ZIP_MD5=`md5 ${UPDATE_TARGET}/${RELEASE_FILE_NAME}.zip | awk -F ' ' '{print $NF}'`
ZIP_SHA1=`shasum -a 1 ${UPDATE_TARGET}/${RELEASE_FILE_NAME}.zip | awk -F ' ' '{print $1}'`
ZIP_SHA256=`shasum -a 256 ${UPDATE_TARGET}/${RELEASE_FILE_NAME}.zip | awk -F ' ' '{print $1}'`

cat > "latest.json" <<EOF
{
	"zip": "${RELEASE_FILE_NAME}.zip",
	"zipsig": "${RELEASE_FILE_NAME}.zip.sig",
	"zipsigasc": "${RELEASE_FILE_NAME}.zip.sig.asc",
	"manifest": "${RELEASE_FILE_NAME}.manifest",
	"urlbase": "http://updates.duplicati.com/${RELEASE_TYPE}/",
	"link": "http://updates.duplicati.com/${RELEASE_TYPE}/${RELEASE_FILE_NAME}.zip",
	"zipmd5": "${ZIP_MD5}",
	"zipsha1": "${ZIP_SHA1}",
	"zipsha256": "${ZIP_SHA256}"
}
EOF


echo "${RELEASE_FILE_NAME}" > "latest.json"
aws --profile=duplicati-upload s3 cp "latest.json" "s3://updates.duplicati.com/${RELEASE_TYPE}/latest.json"

echo "Propagating to other build types"
for OTHER in ${OTHER_UPLOADS}; do
	aws --profile=duplicati-upload s3 cp "s3://updates.duplicati.com/${RELEASE_TYPE}/${RELEASE_FILE_NAME}.manifest" "s3://updates.duplicati.com/${OTHER}/latest.manifest"
	aws --profile=duplicati-upload s3 cp "s3://updates.duplicati.com/${RELEASE_TYPE}/latest.json" "s3://updates.duplicati.com/${OTHER}/latest.json"
done

rm "${RELEASE_CHANGELOG_NEWS_FILE}"

git checkout "Duplicati/License/VersionTag.txt"
git checkout "Duplicati/Library/AutoUpdater/AutoUpdateURL.txt"
git checkout "Duplicati/Library/AutoUpdater/AutoUpdateBuildChannel.txt"
git add "Updates/build_version.txt"
git add "${RELEASE_CHANGELOG_FILE}"
git commit -m "Version bump to v${RELEASE_VERSION}-${RELEASE_NAME}" -m "You can download this build from: " -m "Binaries: http://updates.duplicati.com/${RELEASE_TYPE}/${RELEASE_FILE_NAME}.zip" -m "Signature file: http://updates.duplicati.com/${RELEASE_TYPE}/${RELEASE_FILE_NAME}.zip.sig" -m "ASCII signature file: http://updates.duplicati.com/${RELEASE_TYPE}/${RELEASE_FILE_NAME}.zip.sig.asc" -m "MD5: ${ZIP_MD5}" -m "SHA1: ${ZIP_SHA1}" -m "SHA256: ${ZIP_SHA256}"
git tag "v${RELEASE_VERSION}-${RELEASE_NAME}"                       -m "You can download this build from: " -m "Binaries: http://updates.duplicati.com/${RELEASE_TYPE}/${RELEASE_FILE_NAME}.zip" -m "Signature file: http://updates.duplicati.com/${RELEASE_TYPE}/${RELEASE_FILE_NAME}.zip.sig" -m "ASCII signature file: http://updates.duplicati.com/${RELEASE_TYPE}/${RELEASE_FILE_NAME}.zip.sig.asc" -m "MD5: ${ZIP_MD5}" -m "SHA1: ${ZIP_SHA1}" -m "SHA256: ${ZIP_SHA256}"
git push --tags

PRE_RELEASE_LABEL="--pre-release"
if [ "${RELEASE_TYPE}" == "stable" ]; then
	PRE_RELEASE_LABEL=""
fi

RELEASE_MESSAGE=`printf "Changes in this version:\n${RELEASE_CHANGEINFO_NEWS}"`

# Using the tool from https://github.com/aktau/github-release

GITHUB_TOKEN=`cat "${GITHUB_TOKEN_FILE}"`

if [ "x${GITHUB_TOKEN}" == "x" ]; then
	echo "No GITHUB_TOKEN found in environment, you can manually upload the binaries"
else
	github-release release ${PRE_RELEASE_LABEL} \
	    --tag "v${RELEASE_VERSION}-${RELEASE_NAME}"  \
	    --name "v${RELEASE_VERSION}-${RELEASE_NAME}" \
	    --repo "duplicati" \
	    --user "duplicati" \
	    --security-token "${GITHUB_TOKEN}" \
	    --description "${RELEASE_MESSAGE}" \

	github-release upload \
	    --tag "v${RELEASE_VERSION}-${RELEASE_NAME}"  \
	    --name "${RELEASE_FILE_NAME}.zip" \
	    --repo "duplicati" \
	    --user "duplicati" \
	    --security-token "${GITHUB_TOKEN}" \
	    --file "${UPDATE_TARGET}/${RELEASE_FILE_NAME}.zip"
fi

echo
echo "Built ${RELEASE_TYPE} version: ${RELEASE_VERSION} - ${RELEASE_NAME}"
echo "    in folder: ${UPDATE_TARGET}"
echo
echo
echo "Building installers ..."

bash "build-installers.sh" "${UPDATE_TARGET}/${RELEASE_FILE_NAME}.zip"


