# RootLog 開発用コンテナ:Firebase エミュレーター(Firestore / Storage / Auth / Functions)と権限ルールのテスト
FROM node:22-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends openjdk-17-jre-headless \
    && rm -rf /var/lib/apt/lists/*

# 名前付きボリュームの持ち主を node ユーザーにするため、先にディレクトリを作っておく
RUN mkdir -p /workspace/firebase/node_modules /workspace/firebase/functions/node_modules /home/node/.cache/firebase \
    && chown -R node:node /workspace /home/node/.cache

# node イメージの node ユーザー(UID 1000)で動かす
USER node
WORKDIR /workspace/firebase

# エミュレーターの本体は初回実行時に ~/.cache/firebase に取得される(ボリュームで保持)
CMD ["bash"]
