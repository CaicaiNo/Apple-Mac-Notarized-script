#! /bin/bash
# Type a script or drag a script file from your workspace to insert its path.

# ###### To user #########
# 1.使用此脚本请将脚本放置于xcodeproj一个目录下
# 2.需要ExportPlist文件对archive操作进行配置，在github的同级目录下，但需要设置为公证账号下的证书id
# 3.xcrun altool --notarize-app 一般会要7-8分钟左右,如果你的网络好,就快，还是要耐心等待
# 若要进行修改,参考 https://blog.csdn.net/shengpeng3344/article/details/103369804
# ########################

# 参数为下面3种
# app-onlybuild 表示仅打包zip和pkg，传到服务器
# app-notarization 表示公证包含app的zip，并打包pkg，传到服务器
# pkg-notarization 表示公证app后，打包进pkg，再进行二次公证，传到服务器

# set -x

NOTARIZED_TYPE=$1
# 公证的 bundle id，在打包pkg时，pkgxxx的bundle id也需要设置这个一致
BUNDLE_ID="com.gensee.xxx"
# apple账号
USERNAME="appledev@xxx.com"
# 这里不是apple账号的密码，而是生成的app密匙，见博客中说明
PASSWORD="xxxx-xxxx-xxxx-amvx"
# 工程名 用于拼接工程.xcodeproj
PRODUCT_NAME="Training"
# 工程中需要编译的target
TARGET="Training"
# pkg的版本号
VERSION="5.13.0"
# proj version
VERSION_PROJ="5.13.0.0"
# buildtime
BUILDTIME=`date "+%y%m%d%H%M"`
# installer 证书用于pkg的product sign
INSTALLER_CER="Developer ID Installer: xxxxx (xxxxxxxx)"
# 是否重新打包acrhive,有时候我们使用脚本仅进行公证
REBUILD=1
# 是否copy到服务器上
SVR_COPY=0

# gensee 部分 - 这里是我自己的处理
deployhost="root@192.168.1.191:/gensee/release/vclass/osx"
# 用于app的zip压缩包
deployhost_app="root@192.168.1.191:/gensee/release/vclass/osx/training.zip"
# 用于pkg的zip压缩包
deployhost_pkg="root@192.168.1.191:/gensee/release/vclass/osx/training_install.zip"





dealVersion()
{
	oldVer=`grep -E "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}" -o -m 1 $1`
	IFS="."
	oldVerVect=($oldVer)
	IFS=""
	i=0
	newVer=""
	for s in ${oldVerVect[@]}
	do
		i=`expr $i + 1`
		if [ $i -eq 4 ]
		then
			newVer="$newVer`expr $s + 1`"
		else
			newVer=${newVer}${s}.
		fi
	done
	echo "#### Upgrade version to file: $1"
	echo "#### Version $oldVer -> $newVer"
	VERSION_PROJ=$newVer
	echo `sed -ig "s/$oldVer/$newVer/g" $1`
}

# 公证func 传入文件路径为参数
function uploadFileAndNotarized()
{
	echo "start notarized $1 ..."
	xcrun altool --notarize-app --primary-bundle-id "$BUNDLE_ID" --username "$USERNAME" --password "$PASSWORD" --file $1 &> tmp
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
	 
	    xcrun altool --notarization-info "$uuid" --username "$USERNAME" --password "$PASSWORD" &> tmp
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
cd "$CURRENT_DIR"
echo "当前project路径为:$CURRENT_DIR"
echo "更新svn工程目录..."
# svn up

# 

if [ ! -d $PROJECT_PATH ]; then
	echo "Archive and Notarization Failed : $PROJECT_PATH not exist"
    exit 1
fi

# gensee add 处理版本号和权限问题
# plist文件可能不同
dealVersion "$CURRENT_DIR/${TARGET}/${TARGET}.plist"

echo "deal version $VERSION_PROJ"

# 获取权限，避免输入密码时被终止
security -v unlock-keychain -p "yourpassword" "$HOME/Library/Keychains/login.keychain"
security -v unlock-keychain -p "yourpassword" "$HOME/Library/Keychains/login.keychain.db"


#参数配置
CONFIGURATION="Release"
EXPORT_PATH="$CURRENT_DIR/Export"
APP_PATH="$EXPORT_PATH/$TARGET.app"
ZIP_PATH="$EXPORT_PATH/${TARGET}${VERSION_PROJ}-${BUILDTIME}.zip"
ARCHIVE_PATH="$EXPORT_PATH/${TARGET}.xcarchive"
FINAL_PKG="$EXPORT_PATH/${TARGET}${VERSION_PROJ}.pkg"

NAME_PKG_ZIP="$EXPORT_PATH/${TARGET}${VERSION_PROJ}-${BUILDTIME}_install.zip"
NAME_APP_ZIP="$ZIP_PATH"



PKGPROJ_PATH="$CURRENT_DIR/$PRODUCT_NAME.pkgproj"
PROJECT_PATH="$CURRENT_DIR/$PRODUCT_NAME.xcodeproj"

# gensee 服务器复制处理
servercopy(){
	if [ $SVR_COPY -eq 0 ]; then
		echo "SVR_COPY is $SVR_COPY , forbid copy action"
		echo "$NAME_APP_ZIP"
		echo "$NAME_PKG_ZIP"
		return 1
	fi
	echo "server copy $NAME_APP_ZIP to $deployhost"
	scp "$NAME_APP_ZIP" "$deployhost"
	echo "server copy $NAME_APP_ZIP to $deployhost_app"
	scp "$NAME_APP_ZIP" "$deployhost_app"
        echo "server copy $NAME_PKG_ZIP to $deployhost"
        scp "$NAME_PKG_ZIP" "$deployhost"
	echo "server copy $NAME_PKG_ZIP to $deployhost_pkg"
	scp "$NAME_PKG_ZIP" "$deployhost_pkg"
        scp "$FINAL_PKG" "$deployhost"
}

# app 打包函数
appAchive(){
	# 打包acrhive
if [ $REBUILD -eq 1 ]; then
	echo "####### Archive and Notarization Script / 开始打包流程 appAchive #######"
	rm -r "$EXPORT_PATH"
	mkdir "$EXPORT_PATH"
	if [ -d $EXPORT_PATH ];then
	    echo "EXPORT_PATH=$EXPORT_PATH"
	fi
	xcodebuild archive -project "$PROJECT_PATH"  -scheme "$TARGET" -configuration "$CONFIGURATION" -archivePath "$ARCHIVE_PATH" -UseModernBuildSystem=NO || { echo "Archive and Notarization Failed : xcodebuild archive action failed"; return 1; }
	# 关于动态库的引用关系修改问题，使用install_name_tool指令,由于在工程中附带了脚本进行处理，这里没有写
	xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportOptionsPlist "$CURRENT_DIR/ExportOptions.plist" -exportPath "$EXPORT_PATH"

	# 因为您不能直接将.app包上传到公证服务，所以您需要创建一个包含该应用程序的压缩存档
	ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

	echo "####### Archive and Notarization Script / 完成打包流程 appAchive #######"
	return 0
fi
}


# app 公证函数
appNotarization(){
	echo "####### Archive and Notarization Script / appNotarization start #######"
	# 第一步:公证app
	uploadFileAndNotarized $ZIP_PATH
	if [ $? -ne 0 ];then
	echo "####### Archive and Notarization Script / appNotarization failed #######"
	return 1
	fi
	# 删除原始的app
	rm -r "$APP_PATH"
	# 解压公证后的zip
	unzip "$ZIP_PATH" -d "$EXPORT_PATH"
	# 对app进行stapler,uploadFileAndNotarized方法仅会对zip进行stapler
	xcrun stapler staple "$APP_PATH"

	NAME_APP_ZIP="$EXPORT_PATH/${TARGET}${VERSION_PROJ}-${BUILDTIME}_Notarization.zip"

	mv "$ZIP_PATH" "$NAME_APP_ZIP"

	echo "####### Archive and Notarization Script / appNotarization end #######"
	return 0
}

pkgArchive(){
	echo "####### Archive and Notarization Script / pkgArchive start #######"
    # packges build command line
    /usr/local/bin/packagesbuild --package-version "${VERSION}" "${PKGPROJ_PATH}"

    # 需要配置你的installer证书
    productsign --sign "$INSTALLER_CER" "$EXPORT_PATH/${TARGET}.pkg" "$FINAL_PKG" || { echo "Archive and Notarization Failed : pkg product sign failed"; return 1; }
    # 移除旧的,未签名的pkg文件
    rm "$EXPORT_PATH/${TARGET}.pkg"
    echo "final pkg file is :$FINAL_PKG"

    ditto -c -k  "$FINAL_PKG" "$NAME_PKG_ZIP"

    echo "####### Archive and Notarization Script / pkgArchive end #######"
}

# pkg公证函数
pkgNotarization()
{
	echo "####### Archive and Notarization Script / pkgNotarization start #######"
	if [ ! -f $FINAL_PKG ];then
		echo "pkgNotarization error : $FINAL_PKG not exist ,you should call pgkbuild"
		return 1
	fi
	# 第二步:公证pkg
	uploadFileAndNotarized $FINAL_PKG
	if [ $? -ne 0 ];then
		echo "####### Archive and Notarization Script / pkgNotarization failed #######"
		return 1
	fi
	# 删除掉之前压缩的pkg
	rm -r "$NAME_PKG_ZIP"
	# 重新压缩pkg
	NAME_PKG_ZIP="$EXPORT_PATH/${TARGET}${VERSION_PROJ}-${BUILDTIME}_install_Notarization.zip"
	ditto -c -k  "$FINAL_PKG" "$NAME_PKG_ZIP"

	echo "####### Archive and Notarization Script / pkgNotarization end #######"
	return 0
}

if [[ "$NOTARIZED_TYPE" == "app-onlybuild" ]];then
	appAchive
	pkgArchive
	if [ $? -ne 0 ];then
		exit 1
	fi
    servercopy
elif [[ "$NOTARIZED_TYPE" == "app-notarization" ]];then
	# remove cache
	rm "${HOME}/Library/Caches/com.apple.amp.itmstransporter/UploadTokens/*"

	appAchive
	pkgArchive
	appNotarization
	if [ $? -ne 0 ];then
		exit 1
	fi
	servercopy
elif [[ "$NOTARIZED_TYPE" == "pkg-notarization" ]];then
	# remove cache
	rm "${HOME}/Library/Caches/com.apple.amp.itmstransporter/UploadTokens/*"

	appAchive
	appNotarization
	pkgArchive
	pkgNotarization
	if [ $? -ne 0 ];then
		exit 1
	fi
	servercopy
	echo "####### 已完成app和pkg的两次公证 #######"
else
	echo "####### Archive and Notarization Script / 传入的参数:$NOTARIZED_TYPE 是一个不匹配的值 #######"
fi


