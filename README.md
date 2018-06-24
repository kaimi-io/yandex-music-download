Yandex Music Downloader
=====================

This is a simple command line Perl script for downloading music from Yandex Music (http://music.yandex.ru).
Origin of the script is the following article: https://kaimi.io/2013/11/yandex-music-downloader/

# Usage

```bat
ya.pl [-adkptu] [long options...]
	-p --playlist     playlist id to download
	-k --kind         playlist kind (eg. ya-playlist, music-blog,
	                  music-partners, etc.)
	-a --album        album to download
	-t --track        track to download (album id must be specified)
	-u --url          download by URL
	-d --dir          download path (current direcotry will be used by
	                  default)
	--proxy           HTTP-proxy (format: 1.2.3.4:8888)
	--exclude         skip tracks specified in file
	--include         download only tracks specified in file
	--delay           delay between downloads (in seconds)
	--mobile          use mobile API
	--auth            authorization header (for HQ music if subscription
	                  is active)
	--bitrate         bitrate (eg. 64, 128, 192, 320)

	Bitrate 320 is available only when subscription is active
	and only via mobile API for now (be sure to specify Authorization header value)

	--debug           print debug info during work
	--help            print usage

	--include and --exclude options use weak match i.e. ~/$term/

	Example:
	ya.pl -p 123 -k ya-playlist
	ya.pl -a 123
	ya.pl -a 123 -t 321
	ya.pl -u https://music.yandex.ru/album/215690
	ya.pl -u https://music.yandex.ru/album/215688/track/1710808
	ya.pl -u https://music.yandex.ru/users/ya.playlist/playlists/1257

```

For further assistance don't hesitate to ask for help in GitHub issues or on the blog: https://kaimi.io
