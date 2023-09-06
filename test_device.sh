#!/bin/bash


# if [ $# -ne 7 ]; then
#     echo "Usage: $0 <webdav_url> <webdav_username> <webdav_password> <local_dir> <package_name> <user> <host> <port>"
#     exit 1
# fi

username="$1"
timestamp="$2"
webdav_url="$3"
package_name="$4"
host="$5"
port="$6"

webdav_username="gibeom"
webdav_password="cmr03120727!"
user="root"


download_url="${webdav_url}"

echo "Download URL: $download_url"
echo "Package name: $package_name"

local_dir="/workdir/packages/${username}/${timestamp}"

echo "Creating local directory..."
mkdir -p "$local_dir"
cd "$local_dir"

# Download package file from WebDAV
echo "Downloading package file from WebDAV... (URL: $download_url)"
if curl -u "${webdav_username}:${webdav_password}" -o "${local_dir}/${package_name}" "$download_url"; then
  echo "Download successful!"
else
  echo "Download failed."
  exit 1
fi


# ssh connection for cleanup
echo "Connecting to the embedded device and performing cleanup..."
ssh -p $port ${user}@${host} << EOF
  # remove all files and directories in /home/root/test
  rm -rf /home/root/test/*
EOF

# copy package file to remote device
echo "Copying file to embedded device..."
if scp -P $port "${local_dir}/${package_name}" ${user}@${host}:/home/root/test; then
  echo "Copy successful!"
else
  echo "Copy failed."
  exit 1
fi

# ssh connection for further operations
echo "Connecting to the device..."
ssh -p $port ${user}@${host} << EOF
  # extract the package file
  tar -zxvf /home/root/test/${package_name} -C /home/root/test

  # reqAuto
  cd /home/root/test
  export LD_LIBRARY_PATH=lib
  ./bin/certTool -o reqAuto -i ypkim@autocrypt.io -p admin
  ./sample/autocryptv2x_test

EOF

echo "Done."

echo "Cleaning up local directory..."
cd /workdir
rm -rf "$local_dir"

echo "Script execution completed."




#  #!/bin/bash
# # set project_root_dir
# project_root_dir="/workdir/securityplatform"

# # local package file path
# package_name="AutocryptV2X_camp122_4.0.0-alpha.18_bc35cf756_autotalks_armel32-poky_NTD2_AUTOTALKS-rel.tar.gz"
# package_file="${project_root_dir}/build/autotalks_armel32-poky/camp122/Release/${package_name}"

# # ssh setting
# user="root"
# host="192.168.18.103"
# port="135"

# # ssh connection for cleanup
# echo "Connecting to the embedded device and performing cleanup..."
# ssh -p $port ${user}@${host} << EOF
#   # remove all files and directories in /home/root/test
#   rm -rf /home/root/test/*
# EOF

# # copy package file to remote device
# echo "Copying file to embedded device..."
# scp -P $port $package_file ${user}@${host}:/home/root/test

# # ssh connection for further operations
# echo "Connecting to the device..."
# ssh -p $port ${user}@${host} << EOF

#   # extract the package file
#   tar -zxvf /home/root/test/${package_name} -C /home/root/test

#   # reqAuto
#   cd /home/root/test
#   export LD_LIBRARY_PATH=lib
#   ./bin/certTool -o reqAuto -i ypkim@autocrypt.io -p admin
#   ./sample/autocryptv2x_test

# EOF

# echo "Done."
