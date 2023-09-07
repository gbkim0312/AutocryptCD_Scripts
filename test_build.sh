#!/bin/bash

# express 앱으로 부터 넘겨받은 인자들
commit_num="$1"
username="$2"
timestamp="$3"
type="$4"
toolchain="$5"
standard="$6"
device="$7"
rel="$8"
hw="$9"

project_origin_url="git@bitbucket.org:autocrypt/securityplatform.git"
project_origin_dir="/workdir/securityplatform"

# User 개인의 워크스페이스 생성
user_workspace_dir="/workdir/users/${username}"
mkdir -p "${user_workspace_dir}"

# TODO: work directory를 commit번호 별로 분리
# Directory가 존재하면 현재 커밋 넘버 확인
if [ -d "${user_workspace_dir}/securityplatform" ]; then
    cd "${user_workspace_dir}/securityplatform"

    current_commit_num=$(git rev-parse HEAD)

    # 입력받은 commit_num이 main인 경우
    if [ "$commit_num" == "main" ]; then
        # 리모트 디렉토리 Fetch
        git fetch
        LOCAL=$(git rev-parse @)
        REMOTE=$(git rev-parse @{u})
        # 최신 main 브랜치가 아니면 - commit hash가 다르면 - 강제로 main 브랜치로 checkout
        if [ "$LOCAL" != "$REMOTE" ]; then
            echo "Local branch is not up-to-date with main. Checking out to latest main..."
            git checkout -f main
            git pull
        fi

        # 현재 브랜치를 원격 main 브랜치와 추적하도록 설정
        git branch --set-upstream-to=origin/main main
    # 입력받은 commit_num이 실제 commit number인 경우
    else
        # 현재 커밋 넘버와 요청된 커밋 넘버가 다른 경우 강제로 checkout
        if [ "${current_commit_num:0:7}" != "${commit_num:0:7}" ]; then
            echo "Current commit number: $current_commit_num"
            echo "commit number: $commit_num"
            echo "Commit mismatch. Checking out to $commit_num..."
            git checkout -f $commit_num
        fi
    fi

fi

# 디렉토리가 존재하지 않으면 클론 진행
if [ ! -d "${user_workspace_dir}/securityplatform" ]; then
    if ! git clone "$project_origin_url" "${user_workspace_dir}/securityplatform"; then
        echo "Failed to clone from $project_origin_url. Exiting script."
        exit 1
    fi
    cd "${user_workspace_dir}/securityplatform"
    # commit_num이 main이 아니면 입력받은 커밋 넘버로 checkout하기
    if [ "$commit_num" != "main" ]; then
        if ! git checkout "$commit_num"; then
            echo "Failed to checkout to commit $commit_num. Exiting script."
            exit 1
        fi
    fi
fi

# 현재 커밋 번호 업데이트
current_commit_num=$(git rev-parse HEAD)
document_id=$(uuidgen)

echo "commit hash[0:7]: ${current_commit_num:0:7}"

# 현재 브랜치의 가장 최근 태그 가져오기
raw_tag=$(git describe --tags --abbrev=0)

# 첫 문자 제외하고 나머지 저장
version=${raw_tag:1}

# 만약 태그가 없다면 기본 값을 설정 (예: '4.0.0-alpha.18')
if [ -z "$current_tag" ]; then
    current_tag="4.0.0-alpha.18"
fi

# project 루트 디렉토리
user_project_root_dir="${user_workspace_dir}/securityplatform"
cp "${project_origin_dir}/CMakeLists.txt" "${user_project_root_dir}"

# release 버전과 hw가 지정되어있는 경우 build.sh 옵션으로 추가
rel_option=""
hw_option=""
if [ -n "$rel" ]; then
    rel_option="--atlk=rel$rel"
fi

if [ -n "$hw" ]; then
    hw_option="--hw=$hw"
fi

# 클린빌드를 위해 빌드 폴더 내 모든 파일 및 디렉토리 삭제
rm -rf $user_project_root_dir/build/*

# 입력받은 parameter을 가지고 build.sh 실행.
# 빌드 실패 시 종료 - exit code 1 -
cd $user_project_root_dir
result="building"
if [ "$type" == "device" ]; then
    node /workdir/app/upload_to_firebase.js "${document_id}" "${type}" "${current_commit_num:0:7}" "${device}" "${webdav_url}" "${result}" "${username}" "${toolchain}" "${standard}" "${rel}" "${hw}"
else
    node /workdir/app/upload_to_firebase.js "${document_id}" "${type}" "${current_commit_num:0:7}" "${toolchain}" "${webdav_url}" "${result}" "${username}" "${toolchain}" "${standard}" "${rel}" "${hw}"
fi

if ! ./build.sh --standard=$standard $rel_option $hw_option --toolchain=$toolchain release; then
    result="failed"
    echo "Build failed. Exiting script."
    if [ "$type" == "device" ]; then
        node /workdir/app/upload_to_firebase.js "${document_id}" "${type}" "${current_commit_num:0:7}" "${device}" "${webdav_url}" "${result}" "${username}" "${toolchain}" "${standard}" "${rel}" "${hw}"
    else
        node /workdir/app/upload_to_firebase.js "${document_id}" "${type}" "${current_commit_num:0:7}" "${toolchain}" "${webdav_url}" "${result}" "${username}" "${toolchain}" "${standard}" "${rel}" "${hw}"
    fi
    exit 1
fi
# 빌드 후 Package 생성
cd ${user_project_root_dir}/build/$toolchain/$standard/Release
ninja package

# Webdav 서버로 패키지파일 업로드
package_name="AutocryptV2X_${standard}_${version}_${current_commit_num:0:9}_${toolchain}_NTD2_${hw}-rel.tar.gz"
remote_base_dir="/srv/dev-disk-by-uuid-01D95BDE6FE9C940/autocrypt_v2x"


# type 변수가 'device'인 경우 remote_dir 설정
if [ "$type" == "device" ]; then
    if [ "$commit_num" == "main" ]; then
        remote_relative_dir="$username/devices/main_${current_commit_num:0:7}/$device/$timestamp"
    else
        remote_relative_dir="$username/devices/$commit_num/$device/$timestamp"
    fi
else
    if [ "$commit_num" == "main" ]; then
        remote_relative_dir="$username/toolchains/main_${current_commit_num:0:7}/$timestamp"
    else
        remote_relative_dir="$username/toolchains/$commit_num/$timestamp"
    fi
fi

remote_dir="${remote_base_dir}/${remote_relative_dir}"
webdav_url="http://gibeom.tplinkdns.com:9999/autocrypt_v2x/${remote_relative_dir}/${package_name}"

# 명령어 시도 실패 시 다시 실행하는 함수
retry_command() {

    local cmd="$@"  #이 전 명령어
    local retry_count=0
    local max_retries=10
    local wait_time=3

    # 표준 오류 - stderr - 을 표준출력으로 리디렉션 후 output변수에 저장
    until output=$(eval "$cmd" 2>&1); do
        # "No such file or directory" 메시지 포함 여부 확인
        if echo "$output" | grep -q "No such file or directory"; then
            echo "Cannot create the package. Skipping..."
            return 1
        fi

        ((retry_count++))
        # retrycount가 max_retries보다 큰 경우, 스킵함
        if [ $retry_count -ge $max_retries ]; then
            echo "Failed after $max_retries attempts. Skipping..."
            return 1
        fi
        # wait_time만큼 sleep한 뒤, 다시 실행
        echo "Failed to execute command. Retrying in $wait_time seconds..."
        sleep $wait_time
    done
}

# 로컬에 패키지 파일이 존재하는지 검사
if [ -f "${user_project_root_dir}/build/$toolchain/$standard/Release/$package_name" ]; then
    # 원격 서버에 디렉토리 생성
    retry_command sshpass -p "dslove1109" ssh -p 55 pi@gibeom.tplinkdns.com "mkdir -p $remote_dir"

    # 패키지 파일을 원격 서버로 SCP 복사
    cd ${user_project_root_dir}/build/$toolchain/$standard/Release
    if retry_command sshpass -p "dslove1109" scp -P 55 ./$package_name "pi@gibeom.tplinkdns.com:$remote_dir"; then
        # 만약 scp 명령어가 성공적으로 종료되었을 때
        echo "Uploaded to: $webdav_url"
        result="success"
    else
        echo "$package_name upload failed."
        result="failed"
        # exit 1
    fi
else
    echo "$package_name does not exist. Skipping upload..."
    result="failed"
    # exit 1
fi

if [ "$type" == "device" ]; then
    node /workdir/app/upload_to_firebase.js "${document_id}" "${type}" "${current_commit_num:0:7}" "${device}" "${webdav_url}" "${result}" "${username}" "${toolchain}" "${standard}" "${rel}" "${hw}"
else
    node /workdir/app/upload_to_firebase.js "${document_id}" "${type}" "${current_commit_num:0:7}" "${toolchain}" "${webdav_url}" "${result}" "${username}" "${toolchain}" "${standard}" "${rel}" "${hw}"
fi

if [ "$result" == "failed" ]; then
    exit 1
fi