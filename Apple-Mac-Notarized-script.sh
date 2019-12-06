#! /bin/bash
# Type a script or drag a script file from your workspace to insert its path.

# ###### To user #########
# 1.使用此脚本请将脚本放置于xcodeproj一个目录下
# 2.需要ExportPlist文件对archive操作进行配置，在github的同级目录下，但需要设置为公证账号下的证书id
# 3.xcrun altool --notarize-app 一般会要7-8分钟左右,如果你的网络好,就快，还是要耐心等待
# ########################

# 0表示公证包含app的zip
# 1表示公证pkg包
# 3表示公证app后，打包进pkg，再进行二次公证
NOTARIZED_TYPE=1
# 公证的 bundle id，在打包pkg时，pkg的bundle id也需要设置这个一致 com.gensee.xxxx
BUNDLE_ID="com.gensee.xxxx"
# apple账号，开发者的登陆账号
USERNAME="appledev@xxx.com"
# 这里不是apple账号的密码!，而是生成的app密匙，见博客中说明
PASSWORD="cgki-xxxx-xxxx-amvx"
# 工程名 用于拼接工程.xcodeproj
PRODUCT_NAME="Webcast"
# 工程中需要编译的target
TARGET="Webcast"
# pkg的版本号
VERSION="5.8.3"
# installer 证书用于pkg的product sign - 见博客说明，是专门用于pkg打包的证书，与Develop ID的证书不同
INSTALLER_CER="Developer ID Installer: XXXXX (XXXXXXXXXX)"
# 是否重新打包acrhive,有时候我们使用脚本仅进行公证
REBUILD=0
# 公证func 传入文件路径为参数
function uploadFileAndNotarized()
{
echo "start notarized $1 ..."
xcrun altool --notarize-app --primary-bundle-id $BUNDLE_ID --username $USERNAME --password $PASSWORD --file $1 &> tmp
# 从日志文件中读取UUID,并隔一段时间检查一次公证结果
# 只有成功的格式是 RequestUUID =
uuid=`cat tmp | grep -Eo 'RequestUUID = [[:alnum:]]{8}-([[:alnum:]]{4}-){3}[[:alnum:]]{12}' | grep -Eo '[[:alnum:]]{8}-([[:alnum:]]{4}-){3}[[:alnum:]]{12}' | sed -n "1p"`
# 如果上传过了，则会返回 The upload ID is
if [[ "$uuid" == "" ]];then
uuid=`cat tmp | grep -Eo 'The upload ID is [[:alnum:]]{8}-([[:alnum:]]{4}-){3}[[:alnum:]]{12}' | grep -Eo '[[:alnum:]]{8}-([[:alnum:]]{4}-){3}[[:alnum:]]{12}' | sed -n "1p"`
echo "The software asset has already been uploaded. The upload ID is $uuid"
fi
echo "notarization UUID is $uuid"
# 即没有上传成功，也没有上传过，则退出
if [[ "$uuid" == "" ]]; then
echo "No success no uploaded, unknown error"
cat tmp  | awk 'END {print}'
return 1
fi

while true; do
echo "checking for notarization..."

xcrun altool --notarization-info "$uuid" --username $USERNAME --password $PASSWORD &> tmp
r=`cat tmp`
t=`echo "$r" | grep "success"`
f=`echo "$r" | grep "invalid"`
if [[ "$t" != "" ]]; then
echo "notarization done!"
xcrun stapler staple "$1"
# xcrun stapler staple "Great.dmg"
echo "stapler done!"
break
fi
if [[ "$f" != "" ]]; then
echo "Failed : $r"
return 1
fi
echo "not finish yet, sleep 1min then check again..."
sleep 60
done
return 0
}



echo "####### Archive and Notarization Script / Webcast打包公证脚本 #######"
#Webcast打包公证脚本

#进入当前文件路径 - 请放置在Webcast工程文件路径下
CURRENT_DIR=$(dirname $0)
cd CURRENT_DIR
echo "当前脚本路径为:$CURRENT_DIR"

PROJECT_PATH="$CURRENT_DIR/$PRODUCT_NAME.xcodeproj"

if [ ! -d $PROJECT_PATH ]; then
echo "Archive and Notarization Failed : $PROJECT_PATH not exist"
exit 1
fi
# 参数配置
CONFIGURATION="Release"
EXPORT_PATH="$CURRENT_DIR/Export"
APP_PATH="$EXPORT_PATH/$PRODUCT_NAME.app"
ZIP_PATH="$EXPORT_PATH/$PRODUCT_NAME.zip"
ARCHIVE_PATH=$EXPORT_PATH/${TARGET}.xcarchive

# 打包acrhive
if [ $REBUILD -eq 1 ]; then
echo "####### Archive and Notarization Script / 开始打包流程 #######"
rm -r "$EXPORT_PATH"
mkdir "$EXPORT_PATH"
if [ -d $EXPORT_PATH ];then
echo "EXPORT_PATH=$EXPORT_PATH"
fi
xcodebuild archive -project "$PROJECT_PATH"  -scheme $TARGET -configuration "$CONFIGURATION" -archivePath "$ARCHIVE_PATH" || { echo "Archive and Notarization Failed : xcodebuild archive action failed"; exit 1; }
# 关于动态库的引用关系修改问题，使用install_name_tool指令,由于在工程中附带了脚本进行处理，这里没有写
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportOptionsPlist "$CURRENT_DIR/ExportOptions.plist" -exportPath "$EXPORT_PATH"

echo "####### Archive and Notarization Script / 完成打包流程 #######"
fi


appNotarization(){
echo "####### Archive and Notarization Script / 开始App公证 #######"
# 因为您不能直接将.app包上传到公证服务，所以您需要创建一个包含该应用程序的压缩存档,当使用pkg时可以忽略
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
# As a convenience, open the export folder in Finder. if you want open the folder
# open "$EXPORT_PATH"
# 第一步:公证app
uploadFileAndNotarized $ZIP_PATH
if [ $? -ne 0 ];then
echo "####### Archive and Notarization Script / 公证App失败 #######"
return 1
fi
# 删除原始的app
rm -r "$APP_PATH"
# 解压公证后的zip
unzip "$ZIP_PATH" -d "$EXPORT_PATH"
# 对app进行stapler,uploadFileAndNotarized方法仅会对zip进行stapler
xcrun stapler staple "$APP_PATH"

echo "####### Archive and Notarization Script / 完成App公证 #######"
return 0
}

pkgNotarization()
{
echo "####### Archive and Notarization Script / 开始Pkg公证 #######"

PKGPROJ_PATH=$CURRENT_DIR/$PRODUCT_NAME.pkgproj
# packges build command line
/usr/local/bin/packagesbuild --package-version ${VERSION} ${PKGPROJ_PATH}

FINAL_PKG="$EXPORT_PATH/${TARGET}_$VERSION.pkg"
# 需要配置你的installer证书
productsign --sign "$INSTALLER_CER" "$EXPORT_PATH/${TARGET}.pkg" "$FINAL_PKG" || { echo "Archive and Notarization Failed : pkg product sign failed"; exit 1; }
# 移除旧的,未签名的pkg文件
rm $EXPORT_PATH/${TARGET}.pkg
echo "final notarized pkg file is :$FINAL_PKG"
# 第二步:公证pkg
uploadFileAndNotarized $FINAL_PKG
if [ $? -ne 0 ];then
echo "####### Archive and Notarization Script / 公证Pkg失败 #######"
return 1
fi
echo "####### Archive and Notarization Script / 完成Pkg公证 #######"
return 0
}

if [ $NOTARIZED_TYPE -eq 0 ];then
appNotarization
if [ $? -ne 0 ];then
exit 1
fi
elif [ $NOTARIZED_TYPE -eq 1 ];then
pkgNotarization
if [ $? -ne 0 ];then
exit 1
fi
else
appNotarization
if [ $? -ne 0 ];then
exit 1
fi
pkgNotarization
if [ $? -ne 0 ];then
exit 1
fi
echo "####### 已完成app和pkg的两次公证 #######"
fi
