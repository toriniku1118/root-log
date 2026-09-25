# RootLog 開発用コンテナ:Flutter + Android SDK
# Ubuntu PC 上で Android 版のビルド・実機での実行(ホットリロード)を行う。
# iOS 版は Linux ではビルドできないため、Codemagic(macOS のクラウドビルド)で行う。
FROM ubuntu:24.04

ARG FLUTTER_VERSION=stable
# Android コマンドラインツールの版は https://developer.android.com/studio#command-line-tools-only で最新を確認
ARG ANDROID_CMDLINE_TOOLS=11076708
ARG ANDROID_PLATFORM=android-35
ARG ANDROID_BUILD_TOOLS=35.0.0
# ホストのユーザーと同じ UID/GID にして、作ったファイルの持ち主がずれないようにする
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    FLUTTER_HOME=/opt/flutter \
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH=${FLUTTER_HOME}/bin:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${PATH}

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils zip sudo usbutils \
      openjdk-17-jdk-headless \
      clang cmake ninja-build pkg-config libgtk-3-dev \
    && rm -rf /var/lib/apt/lists/*

# 一般ユーザー(ubuntu:24.04 には UID 1000 の ubuntu ユーザーがいるため作り直す)
RUN userdel -r ubuntu 2>/dev/null || true \
    && groupadd -g ${USER_GID} dev \
    && useradd -m -u ${USER_UID} -g ${USER_GID} -G plugdev -s /bin/bash dev \
    && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev

# Android SDK
RUN mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools \
    && curl -fsSL -o /tmp/cmdline.zip https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS}_latest.zip \
    && unzip -q /tmp/cmdline.zip -d ${ANDROID_SDK_ROOT}/cmdline-tools \
    && mv ${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools ${ANDROID_SDK_ROOT}/cmdline-tools/latest \
    && rm /tmp/cmdline.zip \
    && yes | sdkmanager --licenses >/dev/null \
    && sdkmanager "platform-tools" "platforms;${ANDROID_PLATFORM}" "build-tools;${ANDROID_BUILD_TOOLS}" \
    && chown -R dev:dev ${ANDROID_SDK_ROOT}

# Flutter
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git ${FLUTTER_HOME} \
    && chown -R dev:dev ${FLUTTER_HOME}

# 名前付きボリュームの持ち主を dev ユーザーにするため、先にディレクトリを作っておく
RUN mkdir -p /home/dev/.gradle /home/dev/.android /home/dev/.pub-cache /workspace/app \
    && chown -R dev:dev /home/dev /workspace

USER dev
RUN flutter config --no-analytics \
    && flutter precache --android \
    && yes | flutter doctor --android-licenses >/dev/null || true

# Firebase の設定ファイル生成ツール(flutterfire configure)
RUN dart pub global activate flutterfire_cli
ENV PATH=/home/dev/.pub-cache/bin:${PATH}

WORKDIR /workspace/app
CMD ["bash"]
