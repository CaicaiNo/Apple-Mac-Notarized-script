# Apple-Mac-Notarized-script

Mac公证打包脚本
需要自行配置

1.证书

2.工程名

3.选用的打包形式

4.Developer Installer证书

5.苹果账号

6.ExportPlist文件信息

7.打包pkg需要下载Packges,见 https://blog.csdn.net/shengpeng3344/article/details/103375025

8.钥匙串需要电脑密码，请将yourpassword改为你的密码，loginkeychain是否正确也因人而异


若需要参考，前往博客 https://blog.csdn.net/shengpeng3344/article/details/103369804

另外动态库的引用关系没有在这里处理，放在了工程脚本中处理。见 https://blog.csdn.net/shengpeng3344/article/details/103203179

# Usage

脚本调用使用终端命令：`sh Apple-Mac-Notarized-script.h app-notarization`

`app-notarization`为参数，可以配置，为下面3种

1. app-onlybuild 表示仅打包zip和pkg，传到服务器
2. app-notarization 表示公证包含app的zip，并打包pkg，传到服务器
3. pkg-notarization 表示公证app后，打包进pkg，再进行二次公证，传到服务器

# 2024.02.20 
## web公证脚本

从 2023.11.01 起，老的公证方式不再支持，这里需要切换为 web 公证方式, 你需要替换老的脚本中公证部分的处理

https://blog.csdn.net/shengpeng3344/article/details/136197460
​
脚本文件 

替换你的秘钥文件 (例如 AuthKey_2X9R4HXF34.p8)
```c
private_key = f"./../../res/AuthKey_2X9R4HXF34.p8"
```
设置你的 kid
```c
# 设置 JWT 的 header
jwt_header = {
    "alg": "ES256",
    "kid": "2X9R4HXF34",
    "typ": "JWT"
}
 ```

调用脚本
```c
python3 -u ./notarize.py --pkg "./Output/${PACKAGE_NAME}_$TIME_INDEX.pkg" --private-key "./../../res/AuthKey_2X9R4HXF34.p8"

if [ $? -eq 0 ]; then
    echo "./Output/aTrustInstaller_$TIME_INDEX.pkg notarization successful"
    // 公证成功
else
    // 公证失败
    echo "./Output/aTrustInstaller_$TIME_INDEX.pkg notarization failed"
    exit 1
fi
```

​
