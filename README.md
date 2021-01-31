# Ec2discord

AWS EC2インスタンスの制御を行うDiscord botを開発するためのrubygemsです。主に日本語で開発されています。

- Discordのテキストチャネルに簡単なコマンドを入力するだけで，EC2インスタンスの起動・停止を行うことができます。
   - マルチプレイ用ゲームサーバ，必要な時だけ使うファイル転送サーバ，開発環境用EC2インスタンスなどに活用することを想定しています。
- サーバ停止時，突然シャットダウンするのではなく，サービス停止と `shutdown` コマンドによる停止が可能です。
   - 例えば，サービス停止時にあらかじめデータのバックアップ処理を仕込んでおくことで，終了前に毎回自動バックアップ取得が可能です。

## 準備

AWSのインスタンスを立ち上げるためにAWS Lambdaを，AWS Lambdaを立ち上げるためにAmazon API Gatewayを使います。まずは，これらを組み合わせ，所望のインスタンスが立ち上がるようなエンドポイントを作成します。

まず，Lambdaには以下のようなコードでインスタンスの立ち上げ関数を設定します。環境変数として`instance_id`と`region`を設定するのを忘れないようにしてください。

```python
import boto3
import os

def lambda_handler(event, context):

    ec2 = boto3.client('ec2', region_name=os.environ['region'])
    ec2.start_instances(InstanceIds=[os.environ['instance_id']])
    print('Instance ' + os.environ['instance_id'] + ' Started')
```

そのうえで，LambdaのトリガーにAPI Gatewayを加えることで，REST APIによるインスタンスが起動が可能となります。作成したエンドポイントは覚えておいてください。

## Instal

Gemfileに以下の行を追加します。

```ruby
gem 'ec2discord', git: 'git://github.com/highemerly/ec2discord.git'
```

そのうえで，以下のように，bundlerを使って入手してください。

    $ bundle install

または，手動でインストールすることも可能です。

    $ gem specific_install -l 'git://github.com/highemerly/ec2discord.git'

## Usage

### `.env` の準備

Ec2discordでは `DotEnv` が使われています。起動前に .env ファイルに設定を適切に記入する必要があります。サンプルを入手し，コメントを参考に適切に設定してください。

    $ wget https://raw.githubusercontent.com/highemerly/ec2discord/master/.env.template
    $ cp .env.template .env
    $ vi .env

Discordとの連携のためにIDとトークンが必要です。あらかじめ[Discord](https://discordapp.com/developers/applications)のAPIページでアプリケーションを作成し，IDとトークンを作成してください。詳細は[Discord開発者サイト](https://discord.com/developers/docs/intro)を参考にしてください。

`AWS_EC2START_URI` には先ほど作成したインスタンス起動用のエンドポイントを設定します。

### 実装

```ruby

require 'ec2discord'

bot = Ec2discord::Bot.new
bot.run

```

###

## 高度な使い方

### 非ElasticIP環境の場合にIPアドレスを自動取得する

非ElasticIP環境の場合，起動の度にIPv4アドレスが変わってしまいます。そこで，

1. TCPソケット通信：使ってパブリックIPv4を通知
1. DNSレコード更新：通知されたIPv4アドレスを元に特定DNSサービス（現状はCloudFlareのみ）のAレコードを更新

する仕組みが利用できます。

#### 1. TCPソケット通信

Ec2Discordはサーバとして動作します。クライアント側はEC2インスタンスとなるため，EC2インスタンス側に指定のバイナリを転送し，必要なときに起動できるよう設定しなくてはなりません。

- サーバ： `.env` ファイル

以下のとおり，TCPソケットサーバを有効化したうえで，待ち受けポートを設定します。

```
SOCKET_SERVER=true
SOCKET_SERVER_PORT="9002"
```

- クライアント： バイナリ

バイナリファイルは以下に配置されています。

https://github.com/highemerly/ec2discord-tcpclient/tree/main/dist

このバイナリのうち適切なものをEC2サーバに配置し，起動後自動で起動するように設定します。起動時にはサーバアドレス（Ec2Discordが動作しているサーバのIPv4アドレス）および待ち受けポート番号を引数に与える必要があります。

```
./ec2discord-tcpclient -host <サーバアドレス> -port 9002
```

#### 2. DNSレコード更新

通知したIPv4アドレスを元にAレコードを更新できます。現在CloudFlare v4 APIにのみ対応しています。一般に，Aレコードを更新しても，インターネット上のすべての端末にすぐに適用される訳ではありません。TTLを非常に短くするか，CloudFlare側でプロキシさせるなどの対応が必要と想定されます。

- 準備： `.env` ファイル

あらかじめCloudFlareに登録し，何らかのAレコードを設定しておいてください。その上で `.env` に以下の設定を行います。

```
CLOUDFLARE=true
CLOUDFLARE_API_TOKEN="........."
CLOUDFLARE_ZONE_ID="........."
CLOUDFLARE_DOMAIN="example.com,img.example.com,blog.example.com"
```

- 起動：

起動後，TCPソケットで受信した信号に応じ，自動でCloudFlare APIを叩いてAレコードを更新できます。

### 追加機能の開発

botへ機能追加を行う場合，以下のようにbotクラスを継承します。Ec2discordでは，rubygemの `discordrb` が使われているため，setupメソッドに追加コマンドを実装することで任意のコマンドが実装可能です。

```ruby

require 'ec2discord'

class MyBot < Ec2discord::Bot
	def setup
		super
		@bot.command :omikuji do |event|
      t = Array[
        "大吉",
        "中吉",
        "小吉",
        "吉",
        "凶",
      ]
      r = rand(0..t.size-1)
      event.user.name + "さんの今日の運勢は" + t[r] + "です。"
    end
  end
end

bot = MyBot.new
bot.run

```

また，追加機能開発の例としては以下があります。

- [ec2craft](https://github.com/highemerly/ec2craft): Minecraftサーバの管理Bot

## Contributing

https://github.com/highemerly/ec2discord.