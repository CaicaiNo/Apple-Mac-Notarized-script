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
