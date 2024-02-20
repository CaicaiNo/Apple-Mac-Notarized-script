#!/usr/bin/env python3

import sys
import hashlib
import jwt
from jwt.exceptions import ExpiredSignatureError
import datetime
import os
import requests
import boto3
from botocore.config import Config
import json
import subprocess
import time
import argparse

# 获取 jwt token
# 1. 尝试获取上一次缓存的token
# 2. 缓存的token失效，则重新生成
private_key=None
def get_jwt_token():
    global private_key
    if not private_key:
        private_key = f"./../../res/AuthKey_2X9R4HXF34.p8"
    # 检查文件是否存在
    if os.path.exists(private_key):
        # 读取私钥文件内容
        with open(private_key, 'rb') as f:
            jwt_secret_key = f.read().decode()
    else:
        print('[error]','%s not exist' % (private_key))
        exit(1)

    # 获取当前时间
    now = datetime.datetime.now()
    # 计算过期时间（当前时间往后 20 分钟）
    expires = now + datetime.timedelta(minutes=20)

    # 设置 JWT 的 header
    jwt_header = {
        "alg": "ES256",
        "kid": "2X9R4HXF34",
        "typ": "JWT"
    }

    # 检查文件是否存在
    if os.path.exists("./jwt_token"):
        # 读取
        with open('./jwt_token', 'rb') as f:
            jwt_pre_token = f.read().decode()

        
        print('[info]','jwt token %s' % (jwt_pre_token))
        try:
            decoded = jwt.decode(
                jwt_pre_token,
                jwt_secret_key,
                algorithms="ES256",
                audience="appstoreconnect-v1"
            )
        except Exception as e:
            print('[error]', 'decode exception %s' % (e))
        else:
            exp = datetime.datetime.fromtimestamp(decoded["exp"])

            if exp - datetime.timedelta(seconds=60) < now:
                print('[info]',"JWT Token 已过期，重新生成")
            else:
                print('[info]',"JWT Token 有效，使用之前token")
                return jwt_pre_token

    

    # 设置 JWT 的 payload
    jwt_payload = {
        "iss": "xxx6xxxx-xxxx-xxxx-xxxx-xxxxxccccccc",
        "iat": int(now.timestamp()),
        "exp": int(expires.timestamp()),
        "aud": "appstoreconnect-v1",
        "scope": [
            "GET /notary/v2/submissions",
            "POST /notary/v2/submissions",
        ]
    }
    print('[info]', 'jwt_header %s' % (jwt_header), 'jwt_payload %s' % jwt_payload)
    token = jwt.encode(
             jwt_payload,
             jwt_secret_key,
             algorithm="ES256",
             headers=jwt_header,
        )

    # 打开文件，如果文件不存在则创建文件
    with open("./jwt_token", "w") as f:
        # 将 token 写入文件
        f.write(token)

    print('[info]', 'JWT token create %s' % (token))
    return token

# 获取文件sha256值
def get_sha256(filepath):
    with open(filepath, "rb") as file:
        hash = hashlib.sha256()
        hash.update(file.read())
        return hash.hexdigest()

# 获取文件md5
def get_md5(filepath):
    with open(filepath, "rb") as file:
        data = file.read()
        md5 = hashlib.md5(data).hexdigest()
    return md5

# 获取请求body
def get_body(filepath):
    sha256 = get_sha256(filepath)
    body = {
        "submissionName": filepath,
        "sha256": sha256,
        # "notifications": [{"channel": "webhook", "target": "https://example.com" }]
    }
    return body


file_md5=None
def post_submissison(filepath): 
    global file_md5
    body = get_body(filepath)
    token = get_jwt_token()
    file_md5 = get_md5(filepath)
    
    # 指定文件夹路径
    folder_path = './output'
    # 缓存路径
    cache_path = f"{folder_path}/{file_md5}"
    # 检查文件夹是否存在
    if not os.path.exists(folder_path):
        # 如果文件夹不存在，则创建文件夹
        os.makedirs(folder_path)
    else:
        # 如果文件夹已经存在，则进行相应的处理
        print("[info]", '%s 已经存在' % folder_path)


    # 检查文件是否存在
    if os.path.exists(cache_path):
        # 读取
        with open(cache_path, 'rb') as f:
            string = f.read().decode()
            output = json.loads(string)
            print('[info]', '使用上次 submission s3 上传凭证 = %s' % (output))

    else:
        resp = requests.post("https://appstoreconnect.apple.com/notary/v2/submissions", json=body, headers={"Authorization": "Bearer " + token})
        resp.raise_for_status()
        output = resp.json()
        print('[info]', '获取 submission s3上传凭证 = %s' % (output))
        # 打开文件，如果文件不存在则创建文件
        with open(cache_path, "w") as f:
            # 将 resp 写入文件
            f.write(resp.content.decode())

    # 读取 output 中的内容
    aws_info = output["data"]["attributes"]
    bucket = aws_info["bucket"]
    key = aws_info["object"]
    # sub_id = output["data"]["id"]
    # 如果已经完成了公证
    state = get_submission_state(filepath, True)
    if state == True:
        print('[info]', 'file %s alreay finished notarization' % (filepath))
        staple_pkg(filepath)
        exit(0)
        
    s3 = boto3.client(
             "s3",
             aws_access_key_id=aws_info["awsAccessKeyId"],
             aws_secret_access_key=aws_info["awsSecretAccessKey"],
             aws_session_token=aws_info["awsSessionToken"],
             config=Config(s3={"use_accelerate_endpoint": True})
        )

    print('[info]', 'start upload files ...... please wait 2-15 mins')
    # 上传文件
    s3.upload_file(filepath, bucket, key)
    
    print('[info]', 'upload file complete ...')



def get_submission_state(filepath, once=False):
    print('[info]', 'get_submission_state %s %s ' % (filepath, once))
    global file_md5
    if not file_md5:
        file_md5 = get_md5(filepath)
    # 指定文件夹路径
    folder_path = './output'
    # 缓存路径
    cache_path = f"{folder_path}/{file_md5}"
    # 检查文件是否存在
    if os.path.exists(cache_path):
        # 获取文件大小
        file_size = os.path.getsize(cache_path)
        if file_size == 0:
            # 文件内容为空
            print('[info]', ' %s 内容为空，未获取到submission信息' % (filepath))
            return False
        else:
            # 读取缓存内容
            with open(cache_path, 'rb') as f:
                string = f.read().decode()
                output = json.loads(string)
    else:
        return False

    sub_id = output["data"]["id"]
    url = f"https://appstoreconnect.apple.com/notary/v2/submissions/{sub_id}"
    ret = False
    while True:
        try:
            # 获取submission
            token = get_jwt_token()
            resp = requests.get(url, headers={"Authorization": "Bearer " + token})
            resp.raise_for_status()
        except Exception as e:
            # 异常处理
            print("[Error]", ' %s get status failed, code = %s ' % (filepath,resp.status_code))
            return False
        else:
            # 200 正常返回处理
            # 检查 status
            resp_json = resp.json()
            print('[info]', 'GET %s resp is %s , header is %s' % (url,resp_json,resp.headers))

            status = resp_json["data"]["attributes"]["status"]
            if status == "Accepted":
                print("[info]", ' %s notarization succesfull' % filepath)
                ret = True
                break
            if status == "Invalid":
                print("[info]", ' %s notarization failed' % filepath)
                ret = False
                break
            
            if once == False:
                # 暂停 30 秒
                time.sleep(30)
            else:
                print("[info]", 'get_submission_state run once')
                break
    if once == False:
        print_submission_logs(sub_id)
    return ret
        
def print_submission_logs(identifier):
    try:
        url = f"https://appstoreconnect.apple.com/notary/v2/submissions/{identifier}/logs"
        token = get_jwt_token()
        resp = requests.get(url, headers={"Authorization": "Bearer " + token})
        resp.raise_for_status()
    except Exception as e:
        print("[Error]", '/notary/v2/submissions/%s/logs failed, code = %s ' % (identifier, resp.status_code))
    else:
        resp_json = resp.json()
        print('[info]', 'notarization %s logs is %s' % (identifier, resp_json))
    
def staple_pkg(filepath):
    global file_md5
    if not file_md5:
        file_md5 = get_md5(filepath)
    # 完成公证
    subprocess.run(["xcrun", "stapler", "staple", filepath])
    now = datetime.datetime.now()
    # 验证公证结果
    temp_output_file = f"./temp_file_{file_md5}"
    with open(temp_output_file, "w") as f:
        subprocess.run(["xcrun", "stapler", "validate", filepath], stdout=f, stderr=subprocess.STDOUT)

    # 读取验证结果
    with open(temp_output_file, "r") as f:
        validate_result = f.read()

    os.remove(temp_output_file)
    # 检查验证结果
    if "The validate action worked!" not in validate_result:
        print('[error]',"\033[31m[error] stapler validate invalid, may be notarization failed!\033[0m")
        return False
    else:
        print('[info]','staple_pkg succesfull')
        return True

def main():
    parser = argparse.ArgumentParser(description='notarize pkg from apple.')
    parser.add_argument('--pkg', help='input pkg path')
    parser.add_argument('--private-key', default='./../../res/AuthKey_2X9R4HXF34.p8',
                        help='input private key path')
    if len(sys.argv)>2:
        args = parser.parse_args()
        if ((type(args.pkg) is not str) or (not os.path.isfile(args.pkg))):
            print('[error] arg (%s) is not a file!' % (args.pkg))
            exit(1)
        
        if ((type(args.private_key) is not str) or (not os.path.isfile(args.private_key))):
            print('[error] arg (%s) is not a file!' % (args.private_key))
            exit(1)
        global private_key
        private_key = args.private_key
        # 请求公证信息
        post_submissison(args.pkg)
        print("get_submission_state start")
        # 查询公证状态
        state = get_submission_state(args.pkg)
        if state == False:
            exit(1)
        state = staple_pkg(args.pkg)
        if state == False:
            exit(1)
        exit(0)
    else:
        print('[error] usage example: python xxxx.py aTrustInstaller.pkg')

if __name__ == "__main__":
    main()
