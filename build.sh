#!/bin/bash

###
#
#  Semi-AIO Script for Building PitchBlack Recovery in CircleCI
#
#  Copyright (C) 2019-2020, Rokib Hasan Sagar <rokibhasansagar2014@outlook.com>
#                           PitchBlack Recovery Project <pitchblacktwrp@gmail.com>
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
###

echo -e "Starting the CI Build Process...\n"

DIR=$(pwd)
mkdir $(pwd)/work && cd work

echo -e "\nInitializing PBRP repo sync..."
echo $(pwd)
repo init -q -u https://github.com/PitchBlackRecoveryProject/manifest_pb.git -b ${MANIFEST_BRANCH} --depth 1
time repo sync -c -q --force-sync --no-clone-bundle --no-tags -j$(nproc --all)
rm -rf vendor/pb
git clone https://github.com/PitchBlackRecoveryProject/vendor_pb -b pb vendor/pb --depth=1

echo -e "\nGetting the Device Tree on place"
git clone --quiet --progress https://$GitHubName:$GITHUB_TOKEN@github.com/PitchBlackRecoveryProject/${CIRCLE_PROJECT_REPONAME} -b ${CIRCLE_BRANCH} device/${VENDOR}/${CODENAME}

if [[ -n ${USE_SECRET_BOOTABLE} ]]; then
    if [[ -n ${PBRP_BRANCH} ]]; then
        unset PBRP_BRANCH
    fi
    if [[ -z ${SECRET_BR} ]]; then
        SECRET_BR="android-9.0"
    fi
    rm -rf bootable/recovery
    git clone --quiet --progress https://$GitHubName:$GITHUB_TOKEN@github.com/PitchBlackRecoveryProject/pbrp_recovery_secrets -b ${SECRET_BR} --single-branch bootable/recovery
elif [[ -n ${PBRP_BRANCH} ]]; then
    rm -rf bootable/recovery
    git clone --quiet --progress https://github.com/PitchBlackRecoveryProject/android_bootable_recovery -b ${PBRP_BRANCH} --single-branch bootable/recovery
fi

if [[ -n $EXTRA_CMD ]]; then
    eval $EXTRA_CMD
    cd $DIR/work
fi

echo -e "\nPreparing Delicious Lunch..."
export ALLOW_MISSING_DEPENDENCIES=true
source build/envsetup.sh
lunch ${BUILD_LUNCH}

# Keep the whole .repo/manifests folder
cp -a .repo/manifests $(pwd)/
echo "Cleaning up the .repo, no use of it now"
rm -rf .repo
mkdir -p .repo && mv manifests .repo/ && ln -s .repo/manifests/default.xml .repo/manifest.xml

make -j$(nproc --all) recoveryimage
echo -e "\nYummy Recovery is Served.\n"

echo "Ready to Deploy"
export TEST_BUILDFILE=$(find $(pwd)/out/target/product/${CODENAME}/PitchBlack*-UNOFFICIAL.zip 2>/dev/null)
export BUILDFILE=$(find $(pwd)/out/target/product/${CODENAME}/PitchBlack*-OFFICIAL.zip 2>/dev/null)
export BUILD_FILE_TAR=$(find $(pwd)/out/target/product/${CODENAME}/*.tar 2>/dev/null)
export UPLOAD_PATH=$(pwd)/out/target/product/${CODENAME}/upload/

mkdir ${UPLOAD_PATH}

if [[ -n ${BUILD_FILE_TAR} ]]; then
    echo "Samsung's Odin Tar available: $BUILD_FILE_TAR"
    cp ${BUILD_FILE_TAR} ${UPLOAD_PATH}
fi

if [[ -n $BUILDFILE ]]; then
    echo "Got the Official Build: $BUILDFILE"
    sudo chmod a+x vendor/pb/pb_deploy.sh && ./vendor/pb/pb_deploy.sh ${CODENAME} ${SFUserName} ${SFPassword} ${GITHUB_TOKEN} ${VERSION} ${MAINTAINER}
    cp $BUILDFILE $UPLOAD_PATH
    export BUILDFILE=$(find $(pwd)/out/target/product/${CODENAME}/recovery.img 2>/dev/null)
    cp $BUILDFILE $UPLOAD_PATH
    ghr -t ${GITHUB_TOKEN} -u ${CIRCLE_PROJECT_USERNAME} -r ${CIRCLE_PROJECT_REPONAME} -n "Latest Release for $(echo $CODENAME)" -b "PBRP $(echo $VERSION)" -c ${CIRCLE_SHA1} -delete ${VERSION} ${UPLOAD_PATH}
elif [[ $TEST_BUILD == 'true' ]] && [[ -n $TEST_BUILDFILE ]]; then
    echo "Got the Unofficial Build: $TEST_BUILDFILE"
    cp $TEST_BUILDFILE $UPLOAD_PATH
    export TEST_BUILDIMG=$(find $(pwd)/out/target/product/${CODENAME}/recovery.img 2>/dev/null)
    cp $TEST_BUILDIMG $UPLOAD_PATH
    ghr -t ${GITHUB_TOKEN} -u ${CIRCLE_PROJECT_USERNAME} -r ${CIRCLE_PROJECT_REPONAME} -n "Test Release for $(echo $CODENAME)" -b "PBRP $(echo $VERSION)" -c ${CIRCLE_SHA1} -delete ${VERSION}-test ${UPLOAD_PATH}
    echo -e "\nSending the Test build info in Maintainer Group\n"
    TEST_LINK="https://github.com/PitchBlackRecoveryProject/${CIRCLE_PROJECT_REPONAME}/releases/download/${VERSION}/$(echo $TEST_BUILDFILE | awk -F'[/]' '{print $NF}')"
    MAINTAINER_MSG="PitchBlack Recovery for ${VENDOR} ${CODENAME} is available Only For Testing Purpose\n\n"
    MAINTAINER_MSG=${MAINTAINER_MSG}"Go to ${TEST_LINK} to download it."
    cd vendor/pb; python3 telegram.py -c "-1001228903553" -M "$MAINTAINER_MSG"; cd -
fi

echo -e "\n\nAll Done Gracefully\n\n"
