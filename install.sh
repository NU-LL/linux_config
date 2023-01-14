#!/bin/bash

if [ -z $1 ];then
    echo "please input install path"
    echo "eg:"
    echo "$0 ."
    echo "$0 ~"
    exit 1
fi

SCRIPT_DIR=$(realpath ${BASH_SOURCE[0]} | xargs dirname)

TARGET_PATH=$(realpath $1)
DEST=${SCRIPT_DIR}
LOG_SUBPATH="."

display_log() {
	# log function parameters to install.log
	[[ -n "${DEST}" ]] && echo "Displaying message: $@" >> "${DEST}"/${LOG_SUBPATH}/output.log

	local tmp=""
	[[ -n $2 ]] && tmp="[\e[0;33m $2 \x1B[0m]"

	case $3 in
		err)
			echo -e "[\e[0;31m error \x1B[0m] $1 $tmp"
			;;

		wrn)
			echo -e "[\e[0;35m warn \x1B[0m] $1 $tmp"
			;;

		ext)
			echo -e "[\e[0;32m o.k. \x1B[0m] \e[1;32m$1\x1B[0m $tmp"
			;;

		info)
			echo -e "[\e[0;32m o.k. \x1B[0m] $1 $tmp"
			;;

		*)
			echo -e "[\e[0;32m .... \x1B[0m] $1 $tmp"
			;;
	esac
}

exit_with_error() {
	local _file
	local _line=${BASH_LINENO[0]}
	local _function=${FUNCNAME[1]}
	local _description=$1
	local _highlight=$2
	_file=$(basename "${BASH_SOURCE[1]}")
	# local stacktrace="$(get_extension_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}")"

	# display_log "ERROR in function $_function" "$stacktrace" "err"
    display_log "ERROR in function $_function" "err"
	display_log "$_description" "$_highlight" "err"
	display_log "Process terminated" "" "info"

	if [[ "${ERROR_DEBUG_SHELL}" == "yes" ]]; then
		display_log "MOUNT" "${MOUNT}" "err"
		display_log "SDCARD" "${SDCARD}" "err"
		display_log "Here's a shell." "debug it" "err"
		bash < /dev/tty || true
	fi

	# TODO: execute run_after_build here?
	# overlayfs_wrapper "cleanup"
	# unlock loop device access in case of starvation
	# exec {FD}> /var/lock/armbian-debootstrap-losetup
	# flock -u "${FD}"

	exit 255
}

function interactive_config_prepare_terminal() {
	if [[ -z $ROOT_FS_CREATE_ONLY ]]; then
		# override stty size
		[[ -n $COLUMNS ]] && stty cols $COLUMNS
		[[ -n $LINES ]] && stty rows $LINES
		TTY_X=$(($(stty size | awk '{print $2}') - 6)) # determine terminal width
		TTY_Y=$(($(stty size | awk '{print $1}') - 6)) # determine terminal height
	fi

	# We'll use this title on all menus
	backtitle="Install script"
}

function interactive_config_system_type() {
	if [[ -z $SYSTEM_TYPE ]]; then

		options+=("archlinux" "Arch Linux")
		options+=("ubuntu" "Ubuntu")
		SYSTEM_TYPE=$(dialog --stdout --title "Choose you system os" --backtitle "$backtitle" --no-tags \
			--menu "Select you system os" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
		unset options
		[[ -z $SYSTEM_TYPE ]] && exit_with_error "No option selected"

	fi
}

function interactive_config_regional_mirror() {
	if [[ -z $REGIONAL_MIRROR ]]; then

		options+=("github" "Github")
		options+=("gitee" "Gitee")
		REGIONAL_MIRROR=$(dialog --stdout --title "Choose regional mirror" --backtitle "$backtitle" --no-tags \
			--menu "Select regional mirror" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
		unset options
		[[ -z $REGIONAL_MIRROR ]] && exit_with_error "No option selected"

	fi
}

function interactive_config_default_shell() {
	if [[ -z $USE_ZSH_DEFAULT_SHELL ]]; then

		options+=("yes" "yes. Modify the default terminal to zsh")
		options+=("no" "No. Do not modify the default terminal")
		USE_ZSH_DEFAULT_SHELL=$(dialog --stdout --title "Modify default terminal?" --backtitle "$backtitle" --no-tags \
			--menu "Select action" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
		unset options
		[[ -z $USE_ZSH_DEFAULT_SHELL ]] && exit_with_error "No option selected"

	fi
}

function interactive_config_install_vim_plugs() {
	if [[ -z $INSTALL_VIM_PLUGS ]]; then

		options+=("yes" "yes. Please help me install vim plugs")
		options+=("no" "No. Please don't install vim plugs for me")
		INSTALL_VIM_PLUGS=$(dialog --stdout --title "Install vim plugs?" --backtitle "$backtitle" --no-tags \
			--menu "Select action" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
		unset options
		[[ -z $INSTALL_VIM_PLUGS ]] && exit_with_error "No option selected"

	fi
}


interactive_config_prepare_terminal

if [ -f ${DEST}/${LOG_SUBPATH}/output.log ];then
    mv ${DEST}/${LOG_SUBPATH}/output.log ${DEST}/${LOG_SUBPATH}/output.log.bak
fi

##################################################################################################
display_log "Start installing dependent software"

interactive_config_system_type
case "${SYSTEM_TYPE}" in
	"archlinux")
        sudo pacman -Syu git vim zsh curl wget dialog coreutils python-pygments nodejs npm
        ;;
	"ubuntu")
        sudo apt install git vim zsh curl wget dialog stty command-not-found python3-pygments
        # vim coc 插件需要最新版 nodejs 支持，ubuntu 默认仓库中的版本较低
        # curl -fsSL https://deb.nodesource.com/setup_19.x | sudo -E bash - && sudo apt install nodejs
        ;;
	*)
		echo "unknown os: ${SYSTEM_TYPE}"
		exit 3
		;;
esac

interactive_config_regional_mirror
case ${REGIONAL_MIRROR} in
    github)
        GITHUB_SOURCE='https://github.com'
        ;;
    gitee)
        GITHUB_SOURCE='https://gitee.com'
        ;;
esac


##################################################################################################
display_log "Start configuring zsh"

interactive_config_default_shell
if [ x"${USE_ZSH_DEFAULT_SHELL}" == x"yes" ];then
    chsh -s $(which zsh)
fi

if [ -d ${TARGET_PATH}/.oh-my-zsh ];then
    display_log "oh-my-zsh has been installed"
    display_log "you can just remove it with \`rm -r ${TARGET_PATH}/.oh-my-zsh\`"

    read -p "Are you sure to remove oh-my-zsh? select 'n' to skip configuring zsh [y/n] " input
    case $input in
        [yY]*)
            display_log "remove ${TARGET_PATH}/.oh-my-zsh"
            # rm -rf ${TARGET_PATH}/.oh-my-zsh
            ;;
        [nN]*)
            display_log "skip configuring zsh"
            SKTP_ZSH_CONFIG="yes"
            ;;
        *)
            echo "Just enter y or n, please."
            exit 1
            ;;
    esac
fi

if [ x"${SKTP_ZSH_CONFIG}" != x"yes" ];then
    display_log "download oh-my-zsh from ${REGIONAL_MIRROR}"
    if [ x"${REGIONAL_MIRROR}" == x"github" ];then
        curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh > install_zsh.sh
        ZSH=${TARGET_PATH}/.oh-my-zsh sh install_zsh.sh --unattended
        rm install_zsh.sh
    else
        curl -fsSL https://gitee.com/mirrors/oh-my-zsh/raw/master/tools/install.sh > install_zsh.sh
        ZSH=${TARGET_PATH}/.oh-my-zsh REPO=mirrors/oh-my-zsh REMOTE=https://gitee.com/mirrors/oh-my-zsh.git sh install_zsh.sh --unattended
        rm install_zsh.sh
    fi

    # install oh-my-zsh plugs
    if [ x"${REGIONAL_MIRROR}" == x"github" ];then
        # zsh-autosuggestions
        git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-${TARGET_PATH}/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
        # zsh-syntax-highlighting
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-${TARGET_PATH}/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
        # powerlevel10k
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-${TARGET_PATH}/.oh-my-zsh/custom}/themes/powerlevel10k
    else
        # zsh-autosuggestions
        git clone https://gitee.com/imirror/zsh-autosuggestions ${ZSH_CUSTOM:-${TARGET_PATH}/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
        # zsh-syntax-highlighting
        git clone https://gitee.com/NU-LL/zsh-syntax-highlighting ${ZSH_CUSTOM:-${TARGET_PATH}/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
        # powerlevel10k
        git clone --depth=1 https://gitee.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-${TARGET_PATH}/.oh-my-zsh/custom}/themes/powerlevel10k
    fi

    # set .zshrc
    sed -i "s/^ZSH_THEME=.*$/ZSH_THEME=\"powerlevel10k\/powerlevel10k\"/g" ${TARGET_PATH}/.zshrc
    sed -i "s/^plugins=/# plugins=/g" ${TARGET_PATH}/.zshrc
    context='\
plugins=(\
git\
z\
dircycle\
last-working-dir\
command-not-found\
sudo\
cp\
docker\
aliases\
zsh-autosuggestions\
zsh-syntax-highlighting\
colored-man-pages\
colorize\
extract\
# screen\
)\
\
# 绑定到快捷键 Alt + Shift + Left / Right\
bindkey \"^[[1;2D\" insert-cycledleft\
bindkey \"^[[1;2C\" insert-cycledright\
\
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE=\"fg=6\"\
'
    sed -i "/^# plugins=/a ${context}" ${TARGET_PATH}/.zshrc
fi


##################################################################################################
display_log "Start configuring vim"


if [ -f ${TARGET_PATH}/.vimrc ];then
    display_log "backup vim configure file: ${TARGET_PATH}/.vimrc --> ${TARGET_PATH}/.vimrc.bak"
    mv ${TARGET_PATH}/.vimrc ${TARGET_PATH}/.vimrc.bak
fi


cat ./vimrc.template > ${TARGET_PATH}/.vimrc 


interactive_config_install_vim_plugs
if [ x"${INSTALL_VIM_PLUGS}" == x"yes" ];then
    # install vim-plug
    if [ x"${REGIONAL_MIRROR}" == x"github" ];then
        curl -fLo ${TARGET_PATH}/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    else
        curl -fLo ${TARGET_PATH}/.vim/autoload/plug.vim --create-dirs https://gitee.com/NU-LL/vim-plug/raw/master/plug.vim
    fi

    # set .vimrc
    cat ./vimrc.plugs.template >> ${TARGET_PATH}/.vimrc 
fi
