# Ec2discord

AWS EC2インスタンスの制御を行うDiscord botを開発するためのrubygemsです。主に日本語で開発されています。

- Discordのtext channelでコマンドを入力することで，EC2インスタンスの起動・停止を行うことができます。
- サーバ停止時，突然シャットダウンするのではなく，サービス停止と `shutdown` コマンドによる停止が可能です。

## Installation

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

Ec2discordでは `DotEnv` が使われています。サンプルを入手し，コメントを参考に適切に設定してください。

    $ wget https://raw.githubusercontent.com/highemerly/ec2discord/master/.env.sample
    $ cp .env.sample .env
    $ vi .env

### 実装

```ruby

require 'ec2discord'

Dotenv.load ".env"

bot = Ec2discord::Bot.new
bot.run

```

### 追加機能の開発

botへ機能追加を行う場合，以下のようにbotクラスを継承します。Ec2discordでは，rubygemの `discordrb` が使われており，setupメソッドに追加コマンドを実装することで任意のコマンドが実装可能です。

```ruby

require 'ec2discord'

Dotenv.load ".env"

class MyBot < Ec2discord::Bot
	def setup
		super
		@bot.command :omikuji do |event|
			t = Array[
				"大吉",
				"中吉",
				"吉",
				"凶"
			]
			r = rand(0..t.size-1)
			event.user.name + "さんは" + t[r] + "です。"
		end
	end
end

bot = MyBot.new
bot.run

```

## Contributing

https://github.com/highemerly/ec2discord.