
#!/bin/bash

# choose arch
dsmodel=$1
case $1 in
 DS3622xs+)
        arch="broadwellnk"
        osid="ds3622xsp"
        echo "arch is Broadwellnk"
        ;;
 RS4021xs+)
        arch="broadwellnk"
        osid="ds4021xsp"
        echo "arch is Broadwellnk"
        ;;
 DVA3221)
        arch="denverton"
        osid="dva3221"
        echo "arch is Denverton"
        ;;
 DS918+)
        arch="apollolake"
        osid="ds918p"
        echo "arch is Apollolake"
        ;;
  DS3615xs)
        arch="bromolow"
        osid="ds3615xs"
        echo "arch is Bromolow"
        ;;
 DS920+)
        arch="geminilake"
        osid="ds920p"
        echo "arch is Geminilake"
        ;;
 *)
        echo "Usage: $dsmodel [DS3622xs+|RS4021xs+|DVA3221|DS918+|DS920+|DS3615xs]"
        exit 1
        ;;
esac



# prepare build tools
sudo apt-get update && sudo apt-get install --yes --no-install-recommends ca-certificates build-essential git libssl-dev curl cpio bspatch vim gettext bc bison flex dosfstools kmod jq qemu-utils device-tree-compiler
root=`pwd`
major=$2
os_version=$3
minor=$4

workpath=${arch}"-"${major}
mkdir $workpath

if [ $minor -ne 0 ];
then
       pat_address="https://global.download.synology.com/download/DSM/criticalupdate/update_pack/"${os_version}"-"${minor}"/synology_"${arch}"_"${dsmodel:2}".pat"
       build_para=${major}"-"${os_version}"u"${minor}
else
       if [ ${major:(-1)} -eq 0 ];
       then pat_address="https://global.download.synology.com/download/DSM/release/"${major:0:3}"/"${os_version}"/DSM_"${dsmodel}"_"${os_version}".pat"
       else pat_address="https://global.download.synology.com/download/DSM/release/"${major}"/"${os_version}"/DSM_"${dsmodel}"_"${os_version}".pat"
       fi
       build_para=${major}"-"${os_version}
fi
echo ${pat_address}
#https://global.download.synology.com/download/DSM/release/7.1/42621/DSM_DS3622xs%2B_42621.pat

mkdir output
cd $workpath


# download redpill
git clone -b develop --depth=1 https://github.com/dogodefi/redpill-lkm.git
git clone -b develop-new --depth=1 https://github.com/ek2rlstk/redpill-load.git

# download syno toolkit
curl --location "https://global.download.synology.com/download/ToolChain/toolkit/7.0/"${arch}"/ds."${arch}"-7.0.dev.txz" --output ds.${arch}-7.0.dev.txz

mkdir ${arch}
tar -C./${arch}/ -xf ds.${arch}-7.0.dev.txz usr/local/x86_64-pc-linux-gnu/x86_64-pc-linux-gnu/sys-root/usr/lib/modules/DSM-7.0/build

# build redpill-lkm
cd redpill-lkm
sed -i 's/   -std=gnu89/   -std=gnu89 -fno-pie/' ../${arch}/usr/local/x86_64-pc-linux-gnu/x86_64-pc-linux-gnu/sys-root/usr/lib/modules/DSM-7.0/build/Makefile
make LINUX_SRC=../${arch}/usr/local/x86_64-pc-linux-gnu/x86_64-pc-linux-gnu/sys-root/usr/lib/modules/DSM-7.0/build dev-v7
read -a KVERS <<< "$(sudo modinfo --field=vermagic redpill.ko)" && cp -fv redpill.ko ../redpill-load/ext/rp-lkm/redpill-linux-v${KVERS[0]}.ko || exit 1
cd ..

# download syno_extract_system_patch # thanks for jumkey's idea.
mkdir synoesp
curl --location https://raw.githubusercontent.com/ek2rlstk/redpill-loader-action/master/misc --output misc
base64 -d misc > patutils.tar
tar -xvf patutils.tar -C synoesp 
cd synoesp

curl --location  ${pat_address} --output ${os_version}.pat
sudo chmod 777 syno_extract_system
sudo chmod 777 syno_extract_patch
mkdir output-pat
if [ $minor -ne 0 ];
then sudo LD_LIBRARY_PATH=. ./syno_extract_patch -vxf ${os_version}.pat -C output-pat
else sudo LD_LIBRARY_PATH=. ./syno_extract_system -vxf ${os_version}.pat -C output-pat
fi

cd output-pat && sudo tar -zcvf ${os_version}.pat * && sudo chmod 777 ${os_version}.pat
read -a os_sha256 <<< $(sha256sum ${os_version}.pat)
echo $os_sha256
if [ $minor -ne 0 ];
then cp ${os_version}.pat ${root}/${workpath}/redpill-load/cache/${osid}_${os_version}u${minor}.pat
else cp ${os_version}.pat ${root}/${workpath}/redpill-load/cache/${osid}_${os_version}.pat
fi

cd ../../


# build redpill-load
cd redpill-load
cp -f ${root}/user_config.${dsmodel}.json ./user_config.json
sed -i '0,/"sha256.*/s//"sha256": "'$os_sha256'"/' ./config/${dsmodel}/${build_para}/config.json
cat ./config/${dsmodel}/${build_para}/config.json

# 7.1.0 must add this ext
if [ ${os_version} -ge 42550 ];
then ./ext-manager.sh add https://raw.githubusercontent.com/ek2rlstk/redpill-load/develop-new/redpill-misc/rpext-index.json
fi
# add optional ext
./ext-manager.sh add https://raw.githubusercontent.com/ek2rlstk/redpill-loader-action/master/driver/e1000e/rpext-index.json
./ext-manager.sh add https://raw.githubusercontent.com/ek2rlstk/redpill-loader-action/master/driver/igb/rpext-index.json
# DS920+ must add this ext
if [ $dsmodel = "DS920+" ];
then ./ext-manager.sh add https://github.com/ek2rlstk/redpill-load/raw/develop-new/redpill-dtb/rpext-index.json
fi
#./ext-manager.sh add https://raw.githubusercontent.com/dogodefi/mpt3sas/offical/rpext-index.json
#./ext-manager.sh add https://raw.githubusercontent.com/jumkey/redpill-load/develop/redpill-virtio/rpext-index.json
#./ext-manager.sh add https://raw.githubusercontent.com/dogodefi/redpill-ext/master/acpid/rpext-index.json
# ./ext-manager.sh add https://raw.githubusercontent.com/dogodefi/mpt3sas/offical/rpext-index.json
# ./ext-manager.sh add https://raw.githubusercontent.com/jumkey/redpill-load/develop/redpill-virtio/rpext-index.json
if [ $minor -ne 0 ];
then sudo ./build-loader.sh ${dsmodel} ${major}'-'${os_version}'u'${minor}
else sudo ./build-loader.sh ${dsmodel} ${major}'-'${os_version}
fi
mv images/redpill-${dsmodel}*.img ${root}/output/
sudo qemu-img convert -O vmdk ${root}/output/redpill-${dsmodel}*.img ${root}/output/redpill-${dsmodel}-${build_para}.vmdk
cd ${root}
