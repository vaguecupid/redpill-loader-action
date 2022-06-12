
#!/bin/bash

# choose arch
dsmodel=$1
case $1 in
 DS3622xs+)
        arch="broadwellnk"
        osid="ds3622xsp"
        echo "arch is Broadwellnk"
        ;;
 DS918+)
        arch="apollolake"
        osid="ds918p"
        echo "arch is Apollolake"
        ;;
 DS920+)
        arch="geminilake"
        osid="ds920p"
        echo "arch is Geminilake"
        ;;
 *)
        echo "Usage: $dsmodel [DS3622xs+|DS918+|DS920+]"
        exit 1
        ;;
esac

# prepare build tools & variables
sudo apt-get update && sudo apt-get install --yes --no-install-recommends ca-certificates build-essential git libssl-dev curl cpio bspatch vim gettext bc bison flex dosfstools kmod jq qemu-utils device-tree-compiler
root=`pwd`
dsmos=($(echo $2 | tr "-" "\n"))
major=${dsmos[0]} # 7.1.0
os_version=${dsmos[1]} # 42661
if [ ${#dsmos[@]} -eq 3 ]; then
    minor=${dsmos[2]} # Update x
else
    minor=0
fi

worktarget=$3 # real / test / vm
redpillext="https://github.com/pocopico/rp-ext/raw/main/redpill/rpext-index.json"

workpath=${arch}"-"${major}
mkdir $workpath

if [ $minor -ne 0 ];
then
       pat_address="https://global.download.synology.com/download/DSM/criticalupdate/update_pack/"${os_version}"-"${minor}"/synology_"${arch}"_"${dsmodel:2}".pat"
       build_para=${major}"-"${os_version}"u"${minor}
       synomodel=${osid}"_"${os_version}"u"${minor}
else
       if [ $major = "7.1.0" ]; then
        pat_address="https://global.download.synology.com/download/DSM/release/7.1/42661-1/DSM_"${dsmodel}"_"${os_version}".pat"
       else
        pat_address="https://global.download.synology.com/download/DSM/release/"${major}"/"${os_version}"/DSM_"${dsmodel}"_"${os_version}".pat"
       fi
       build_para=${major}"-"${os_version}
       synomodel=${osid}"_"${os_version}
fi
echo ${pat_address}

mkdir output
cd $workpath


# download redpill-load
if [ $4 = "yes" ]; then
 git clone -b develop-jun --depth=1 https://github.com/ek2rlstk/redpill-load.git
else
 git clone -b develop-old --depth=1 https://github.com/ek2rlstk/redpill-load.git
fi

# download static redpill-lkm and use it
extension=$(curl -s --location "$redpillext")
echo "Looking for redpill for : $synomodel"
release=$(echo $extension | jq -r -e --arg SYNOMODEL $synomodel '.releases[$SYNOMODEL]')
files=$(curl -s --location "$release" | jq -r '.files[] .url')

for file in $files; do
        echo "Getting file $file"
        curl -s -O $file
        if [ -f redpill*.tgz ]; then
            echo "Extracting module"
            tar xf redpill*.tgz
            rm redpill*.tgz
            strip --strip-debug redpill.ko
        fi
done

if [ -f redpill.ko ] && [ -n $(strings redpill.ko | grep $synomodel) ]; then
       REDPILL_MOD_NAME="redpill-linux-v$(modinfo redpill.ko | grep vermagic | awk '{print $2}').ko"
       mv ${root}/${workpath}/redpill.ko ${root}/${workpath}/redpill-load/ext/rp-lkm/${REDPILL_MOD_NAME}
       echo "Successful use static redpill"
    else
       echo "Module does not contain platorm information for ${synomodel}"
fi

if [ ! -f ${root}/${workpath}/redpill-load/ext/rp-lkm/${REDPILL_MOD_NAME} ]; then
# download redpill-lkm
 git clone -b develop --depth=1 https://github.com/dogodefi/redpill-lkm.git
# download syno toolkit
 curl --location "https://global.download.synology.com/download/ToolChain/toolkit/7.0/"${arch}"/ds."${arch}"-7.0.dev.txz" --output ds.${arch}-7.0.dev.txz

 mkdir ${arch}
 tar -C./${arch}/ -xf ds.${arch}-7.0.dev.txz usr/local/x86_64-pc-linux-gnu/x86_64-pc-linux-gnu/sys-root/usr/lib/modules/DSM-7.0/build

 # build redpill-lkm (if static is not working)
 cd redpill-lkm
 sed -i 's/   -std=gnu89/   -std=gnu89 -fno-pie/' ../${arch}/usr/local/x86_64-pc-linux-gnu/x86_64-pc-linux-gnu/sys-root/usr/lib/modules/DSM-7.0/build/Makefile
 make LINUX_SRC=../${arch}/usr/local/x86_64-pc-linux-gnu/x86_64-pc-linux-gnu/sys-root/usr/lib/modules/DSM-7.0/build dev-v7
 read -a KVERS <<< "$(sudo modinfo --field=vermagic redpill.ko)" && cp -fv redpill.ko ../redpill-load/ext/rp-lkm/redpill-linux-v${KVERS[0]}.ko || exit 1
 cd ..
fi

# download syno_extract_system_patch # thanks for jumkey's idea.
mkdir synoesp
curl --location https://raw.githubusercontent.com/ek2rlstk/redpill-loader-action/master/misc --output misc
base64 -d misc > patutils.tar
tar -xf patutils.tar -C synoesp 
cd synoesp

curl --location  ${pat_address} --output ${os_version}.pat
sudo chmod 777 syno_extract_system
sudo chmod 777 syno_extract_patch
mkdir output-pat
if [ $minor -ne 0 ];
then sudo LD_LIBRARY_PATH=. ./syno_extract_patch -xf ${os_version}.pat -C output-pat
else sudo LD_LIBRARY_PATH=. ./syno_extract_system -xf ${os_version}.pat -C output-pat
fi

cd output-pat && sudo tar -zcf ${os_version}.pat * && sudo chmod 777 ${os_version}.pat
read -a os_sha256 <<< $(sha256sum ${os_version}.pat)
echo $os_sha256
cp ${os_version}.pat ${root}/${workpath}/redpill-load/cache/${synomodel}.pat

cd ../../


# build redpill-load
cd redpill-load
cp -f ${root}/user_config_${worktarget}_${dsmodel}.json ./user_config.json

sed -i '0,/"sha256.*/s//"sha256": "'$os_sha256'"/' ./config/${dsmodel}/${build_para}/config.json
cat ./config/${dsmodel}/${build_para}/config.json

# 7.1.0 must add this ext
if [ ${os_version} -ge 42550 ];
then ./ext-manager.sh add https://github.com/pocopico/redpill-load/raw/develop/redpill-misc/rpext-index.json
fi
# add optional ext
./ext-manager.sh add https://raw.githubusercontent.com/ek2rlstk/rp-ext/master/e1000e/rpext-index.json
./ext-manager.sh add https://github.com/jumkey/redpill-load/raw/develop/redpill-acpid/rpext-index.json
if [ $worktarget = "real" ]; then
 ./ext-manager.sh add https://raw.githubusercontent.com/ek2rlstk/rp-ext/master/igb/rpext-index.json
else
# ./ext-manager.sh add https://raw.githubusercontent.com/jumkey/redpill-load/develop/redpill-virtio/rpext-index.json
 ./ext-manager.sh add https://raw.githubusercontent.com/pocopico/rp-ext/master/mptspi/rpext-index.json
fi

# DS920+ must add this ext
if [ $dsmodel = "DS920+" ]; then 
  ./ext-manager.sh add https://raw.githubusercontent.com/jumkey/redpill-load/develop/redpill-runtime-qjs/rpext-index.json
  ./ext-manager.sh add https://raw.githubusercontent.com/jumkey/redpill-load/develop/redpill-qjs-dtb/rpext-index.json
fi

if [ $4 = "yes" ]; then
 sudo BRP_JUN_MOD=1 BRP_DEBUG=1 BRP_USER_CFG=user_config.json ./build-loader.sh ${dsmodel} ${build_para}
else
 sudo ./build-loader.sh ${dsmodel} ${build_para}
fi

mv images/redpill-${dsmodel}*.img ${root}/output/
if [ $worktarget = "vm" ]; then
 sudo qemu-img convert -O vmdk ${root}/output/redpill-${dsmodel}*.img ${root}/output/redpill-${dsmodel}-${build_para}.vmdk
 sudo rm ${root}/output/redpill-${dsmodel}*.img
fi
cd ${root}
