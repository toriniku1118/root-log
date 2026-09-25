# RootLog 開発用コンテナ:Firebase エミュレーター(Firestore / Storage / Auth / Functions)と権限ルールのテスト
# firebase-tools 15 以降は JDK 21 以上が必要。Debian bookworm の apt には 21 がないため、公式の JRE イメージからコピーする。
FROM eclipse-temurin:21-jre AS jre

FROM node:22-bookworm

COPY --from=jre /opt/java/openjdk /opt/java/openjdk
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# 名前付きボリュームの持ち主を node ユーザーにするため、先にディレクトリを作っておく
RUN mkdir -p /workspace/firebase/node_modules /workspace/firebase/functions/node_modules /home/node/.cache/firebase \
    && chown -R node:node /workspace /home/node/.cache

# node イメージの node ユーザー(UID 1000)で動かす
USER node
WORKDIR /workspace/firebase

# エミュレーターの本体は初回実行時に ~/.cache/firebase に取得される(ボリュームで保持)
CMD ["bash"]
