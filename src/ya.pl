#!/usr/bin/env perl

use utf8;
use strict;
use warnings;
use Encode qw/from_to decode/;
use Encode::Guess;
use File::Basename;
use POSIX qw/strftime/;

use constant IS_WIN => $^O eq 'MSWin32';
use constant
{
	NL => IS_WIN ? "\015\012" : "\012",
	TIMEOUT => 5,
	AGENT => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/84.0.4147.135 Safari/537.36',
	MOBILE_AGENT => 'Dalvik/10.1.0 (Linux; U; Android 10.0; Google Pixel 4 - 10.0.0 - API 29 - 768x1280 Build/LRX29M)',
	YANDEX_BASE => 'https://music.yandex.ru',
	MOBILE_YANDEX_BASE => 'https://api.music.yandex.net',
	MD5_SALT => 'XGRlBW9FXlekgbPrRHuSiA',
	DOWNLOAD_INFO_MASK => '/api/v2.1/handlers/track/%d:%d/web-album_track-track-track-main/download/m?external-domain=music.yandex.ru&overembed=no&__t=%d&hq=%d',
	MOBILE_DOWNLOAD_INFO_MASK => '/tracks/%d/download-info',
	DOWNLOAD_PATH_MASK => 'https://%s/get-mp3/%s/%s?track-id=%s&from=service-10-track&similarities-experiment=default',
	PLAYLIST_INFO_MASK => '/handlers/playlist.jsx?owner=%s&kinds=%d&light=true&madeFor=&withLikesCount=true&lang=ru&external-domain=music.yandex.ru&overembed=false&ncrnd=',
	MOBILE_PLAYLIST_INFO_MASK => '/users/%s/playlists/%d',
	PLAYLIST_REQ_PART => '{"userFeed":"old","similarities":"default","genreRadio":"new-ichwill-matrixnet6","recommendedArtists":"ichwill_similar_artists","recommendedTracks":"recommended_tracks_by_artist_from_history","recommendedAlbumsOfFavoriteGenre":"recent","recommendedSimilarArtists":"default","recommendedArtistsWithArtistsFromHistory":"force_recent","adv":"a","loserArtistsWithArtists":"off","ny2015":"no"}',
	PLAYLIST_FULL_INFO => '/handlers/track-entries.jsx',
	ALBUM_INFO_MASK => '/api/v2.1/handlers/album/%d?external-domain=music.yandex.ru&overembed=no&__t=%d',
	MOBILE_ALBUM_INFO_MASK => '/albums/%d/with-tracks',
	FILE_NAME_PATTERN => '#artist - #title',
	DEFAULT_PERMISSIONS => 755,
	# For more details refer to 'create_track_entry' function
	PATTERN_MP3TAGS_RELS =>
	{
		'number' => 'TRCK',
		'artist' => 'TPE1',
		'title' => 'TIT2',
		'album' => 'TALB',
		'year' => 'TYER',
	},
	FILE_SAVE_EXT => '.mp3',
	COVER_RESOLUTION => '400x400',
	GENERIC_COLLECTION => "\x{441}\x{431}\x{43e}\x{440}\x{43d}\x{438}\x{43a}",
	GENERIC_TITLE => 'Various Artists',
	URL_ALBUM_REGEX => qr{music\.yandex\.\w+/album/(\d+)}is,
	URL_TRACK_REGEX => qr{music\.yandex\.\w+/album/(\d+)/track/(\d+)}is,
	URL_PLAYLIST_REGEX => qr{music\.yandex\.\w+/users/(.+?)/playlists/(\d+)}is,
	RESPONSE_LOG_PREFIX => 'log_',
	TEST_URL => 'https://api.music.yandex.net/users/ya.playlist/playlists/1',
	RENAME_ERRORS_MAX => 5,
	AUTH_TOKEN_PREFIX => 'OAuth ',
	COOKIE_PREFIX => 'Session_id=',
	HQ_BITRATE => '320',
	DEFAULT_CODEC => 'mp3',
	PODCAST_TYPE => 'podcast',
	VERSION => '1.2',
	COPYRIGHT => '© 2013-2021 by Kaimi (https://kaimi.io)',
};
use constant
{
	PLAYLIST_LIKE => 3,
	PLAYLIST_LIKE_TITLE => 'Мне нравится'
};
use constant
{
	DEBUG => 'DEBUG',
	ERROR => 'ERROR',
	INFO => 'INFO',
	OK => 'OK'
};
use constant
{
	WIN_UTF8_CODEPAGE => 65001,
	STD_OUTPUT_HANDLE => 0xFFFFFFF5,
	FG_BLUE => 1,
	FG_GREEN => 2,
	FG_RED => 4,
	BG_WHITE => 112,
	SZ_CONSOLE_FONT_INFOEX => 84,
	FF_DONTCARE => 0 << 4,
	FW_NORMAL => 400,
	COORD => 0x000c0000,
	FONT_NAME => 'Lucida Console'
};

my %log_colors = 
(
	&DEBUG => 
	{
		nix => 'red on_white',
		win => FG_RED | BG_WHITE
	},
	&ERROR => 
	{
		nix => 'red',
		win => FG_RED
	},
	&INFO => 
	{
		nix => 'blue on_white',
		win => FG_BLUE | BG_WHITE
	},
	&OK =>
	{
		nix => 'green on_white',
		win => FG_GREEN | BG_WHITE
	}
);

my %req_modules = 
(
	NIX => [],
	WIN => [ qw/Win32::API Win32API::File Win32::Console/ ],
	ALL => [ qw/Mozilla::CA Digest::MD5 File::Copy File::Spec File::Temp File::Util MP3::Tag JSON::PP Getopt::Long::Descriptive Term::ANSIColor LWP::UserAgent LWP::Protocol::https HTTP::Cookies HTML::Entities/ ]
);

$\ = NL;

my @missing_modules;
for my $module(@{$req_modules{ALL}}, IS_WIN ? @{$req_modules{WIN}} : @{$req_modules{NIX}})
{
	# Suppress MP3::Tag deprecated regex and other warnings
	eval "local \$SIG{'__WARN__'} = sub {}; require $module";
	if($@)
	{
		push @missing_modules, $module;
	}
}

if(@missing_modules)
{
	print 'Please, install this modules: ' . join ', ', @missing_modules;
	exit(1);
}

# PAR issue workaround && different win* approach for Unicode output
if(IS_WIN)
{
	binmode STDOUT, ':unix:utf8';
	# Unicode (UTF-8) codepage
	Win32::Console::OutputCP(WIN_UTF8_CODEPAGE);
	$main::console = Win32::Console->new(STD_OUTPUT_HANDLE);

	# Set console font with Unicode support (only for Vista+ OS)
	if((Win32::GetOSVersion())[1] eq 6)
	{
		# FaceName size = LF_FACESIZE
		Win32::API::Struct->typedef
		(
			CONSOLE_FONT_INFOEX =>
			qw
			{
				ULONG cbSize; 
				DWORD nFont; 
				DWORD dwFontSize;
				UINT FontFamily;
				UINT FontWeight;
				WCHAR FaceName[32];
			}
		);

		Win32::API->Import
		(
			'kernel32',
			'HANDLE WINAPI GetStdHandle(DWORD nStdHandle)'
		);
		Win32::API->Import
		(
			'kernel32',
			'BOOL WINAPI SetCurrentConsoleFontEx(HANDLE hConsoleOutput, BOOL bMaximumWindow, LPCONSOLE_FONT_INFOEX lpConsoleCurrentFontEx)'
		);

		my $font = Win32::API::Struct->new('CONSOLE_FONT_INFOEX');

		$font->{cbSize} = SZ_CONSOLE_FONT_INFOEX;
		$font->{nFont} = 0;
		$font->{dwFontSize} = COORD; # COORD struct wrap
		$font->{FontFamily} = FF_DONTCARE;
		$font->{FontWeight} = FW_NORMAL;
		$font->{FaceName} = Encode::encode('UTF-16LE', FONT_NAME);

		SetCurrentConsoleFontEx(GetStdHandle(STD_OUTPUT_HANDLE), 0, $font);
	}
}
else
{
	binmode STDOUT, ':encoding(utf8)';
}

my ($opt, $usage) = Getopt::Long::Descriptive::describe_options
(
	'Yandex Music Downloader v' . VERSION . NL . NL .
	basename(__FILE__).' %o',
	['playlist|p:i',    'playlist id to download'],
	['kind|k:s',        'playlist kind (eg. ya-playlist, music-blog, music-partners, etc.)'],
	['album|a:i',       'album to download'],
	['track|t:i',       'track to download (album id must be specified)'],
	['url|u:s',         'download by URL'],
	['dir|d:s',         'download path (current direcotry will be used by default)', {default => '.'}],
	['proxy=s',         'HTTP-proxy (format: 1.2.3.4:8888)'],
	['exclude=s',       'skip tracks specified in file'],
	['include=s',       'download only tracks specified in file'],
	['delay=i',         'delay between downloads (in seconds)', {default => 5}],
	['mobile=i',        'use mobile API', {default => 0}],
	['auth=s',          'authorization header for mobile version (OAuth...)'],
	['cookie=s',        'authorization cookie for web version (Session_id=...)'],
	['bitrate=i',       'bitrate (eg. 64, 128, 192, 320)'],
	['pattern=s',       'track naming pattern', {default => FILE_NAME_PATTERN}],
	['path=s',          'path saving pattern', {default => ''}],
	[],
	['Available placeholders: #number, #artist, #title, #album, #year'],
	[],
	['Path pattern will be used in addition to the download path directory'],
	[],
	['Example path pattern: #artist/#album-#year'],
	[],
	['link|l',          'do not fetch, only print links to the tracks'],
	['silent|s',        'do not print informational messages'],
	['debug',           'print debug info during work'],
	['help|h',          'print usage'],
	[],
	['--include and --exclude options use weak match i.e. ~/$term/'],
	[],
	['Example: '],
	[basename(__FILE__) . ' -p 123 -k ya-playlist'],
	[basename(__FILE__) . ' -a 123'],
	[basename(__FILE__) . ' -a 123 -t 321'],
	[basename(__FILE__) . ' -u https://music.yandex.ru/album/215690 --cookie ...'],
	[basename(__FILE__) . ' -u https://music.yandex.ru/album/215688/track/1710808 --auth ...'],
	[basename(__FILE__) . ' -u https://music.yandex.ru/users/ya.playlist/playlists/1257 --cookie ...'],
	[],
	[COPYRIGHT]
);

# Get a modifiable options copy
my %opt = %{$opt};

if( $opt{help} || ( !$opt{url} && !($opt{track} && $opt{album}) && !$opt{album} && !($opt{playlist} && $opt{kind}) )  )
{
	print $usage->text;
	exit(0);
}

if(!$opt{auth} && !$opt{cookie})
{
	info(ERROR, 'Please, specify either mobile app auth header value (--auth) or web version auth cookie (--cookie)');
	info(ERROR, 'It is no longer possible to download full version of tracks without authentication');
	exit(1);
}

if($opt{mobile} && !$opt{auth} && $opt{cookie})
{
	info(ERROR, 'Please, provide --auth instead of --cookie for Mobile API');
	exit(1);
}

if(!$opt{mobile} && $opt{auth} && !$opt{cookie})
{
	info(ERROR, 'Please, provide --cookie instead of --auth for Web API');
	exit(1);
}

if($opt{dir} && !-d $opt{dir})
{
	info(ERROR, 'Please, specify an existing directory');
	exit(1);
}

MP3::Tag->config('id3v23_unsync', 0);
# Fix for "Writing of ID3v2.4 is not fully supported (prohibited now via `write_v24')"
MP3::Tag->config(write_v24 => 1);
# Fix auth token and cookie format if required
my $auth_token = '';
if($opt{mobile} && $opt{auth})
{
	if($opt{auth} !~ /${\(AUTH_TOKEN_PREFIX)}/i)
	{
		$auth_token = AUTH_TOKEN_PREFIX;
	}
	$auth_token .= $opt{auth};
}

my $cookie = '';
if(!$opt{mobile} && $opt{cookie})
{
	if($opt{cookie} !~ /${\(COOKIE_PREFIX)}/i)
	{
		$cookie = COOKIE_PREFIX;
	}
	$cookie .= $opt{cookie};
}

my ($whole_file, $total_size);
my $ua = LWP::UserAgent->new
(
	agent => $opt{mobile} ? MOBILE_AGENT : AGENT,
	default_headers => HTTP::Headers->new
	(
		Authorization => $auth_token,
		X_Retpath_Y => 1,
		Cookie => $cookie
	),
	cookie_jar => HTTP::Cookies->new
	(
		hide_cookie2 => 1
	),
	timeout => TIMEOUT,
	ssl_opts =>
	{
		verify_hostname => $opt{debug} ? 0 : 1,
		SSL_verify_mode => $opt{debug} ? IO::Socket::SSL->SSL_VERIFY_NONE : IO::Socket::SSL->SSL_VERIFY_PEER,
	}
);
my $json_decoder = JSON::PP->new->utf8->pretty->allow_nonref->allow_singlequote;
my @exclude = ();
my @include = ();

if($opt{debug})
{
	print_debug_info();
}

if($opt{proxy})
{
	$ua->proxy(['http', 'https'], 'http://' . $opt{proxy} . '/');
}

if($opt{exclude})
{
	@exclude = read_file($opt{exclude});
}

if($opt{include})
{
	@include = read_file($opt{include});
}

if($opt{url})
{
	if($opt{url} =~ URL_TRACK_REGEX)
	{
		$opt{album} = $1;
		$opt{track} = $2;
	}
	elsif($opt{url} =~ URL_ALBUM_REGEX)
	{
		$opt{album} = $1;
	}
	elsif($opt{url} =~ URL_PLAYLIST_REGEX)
	{
		$opt{kind} = $1;
		$opt{playlist} = $2;
	}
	else
	{
		info(ERROR, 'Invalid URL format');
	}
}

if($opt{album} || ($opt{playlist} && $opt{kind}))
{
	my @track_list_info;
=pod
	info(INFO, 'Checking Yandex.Music availability');

	my $request = $ua->get(TEST_URL);
	if($request->code != 404)
	{
		info(ERROR, 'Yandex.Music is not available');
		exit(1);
	}
	else
	{
		info(OK, 'Yandex.Music is available')
	}
=cut
	if($opt{album})
	{
		info(INFO, 'Fetching album info: ' . $opt{album});

		@track_list_info = get_album_tracks_info($opt{album});

		if(scalar @track_list_info > 0 && $opt{track})
		{
			info(INFO, 'Filtering single track: ' . $opt{track} . ' [' . $opt{album} . ']');
			@track_list_info = grep
			(
				$_->{track_id} eq $opt{track}
				,
				@track_list_info
			);
		}
	}
	else
	{
		info(INFO, 'Fetching playlist info: ' . $opt{playlist} . ' [' . $opt{kind} . ']');

		@track_list_info = get_playlist_tracks_info($opt{playlist});
	}


	if(!@track_list_info)
	{
		info(ERROR, 'Can\'t get track list info');
		exit(1);
	}

	for my $track_info_ref(@track_list_info)
	{
		my $skip = 0;
		for my $title(@exclude)
		{
			if($track_info_ref->{title} =~ /\Q$title\E/)
			{
				$skip = 1;
				last;
			}
		}
		if($skip)
		{
			info(INFO, 'Skipping: ' . $track_info_ref->{title});
			next;
		}

		$skip = 1;
		for my $title(@include)
		{
			if($track_info_ref->{title} =~ /\Q$title\E/)
			{
				$skip = 0;
				last;
			}
		}
		if($skip && $opt{include})
		{
			info(INFO, 'Skipping: ' . $track_info_ref->{title});
			next;
		}

		if(!$track_info_ref->{title})
		{
			info(ERROR, 'Track with non-existent title. Skipping...');
			next;
		}

		if($opt{link})
		{
			print(get_track_url($track_info_ref));
		}
		else
		{
			fetch_track($track_info_ref);

			if($opt{delay} && $track_info_ref != $track_list_info[-1])
			{
				info(INFO, 'Waiting for ' . $opt{delay} . ' seconds');
				sleep $opt{delay};
			}
		}
	}

	info(OK, 'Done!');
}

if(IS_WIN)
{
	$main::console->Free();
}

sub fetch_track
{
	my $track_info_ref = shift;

	$track_info_ref->{title} =~ s/\s+$//;
	$track_info_ref->{title} =~ s/[\\\/:"*?<>|]+/-/g;

	info(INFO, 'Trying to fetch track: '.$track_info_ref->{title});

	my $track_url = get_track_url($track_info_ref);
	if(!$track_url)
	{
		info(ERROR, 'Can\'t get track url');
		return;
	}

	my $file_path = download_track($track_url);
	if(!$file_path)
	{
		info(ERROR, 'Failed to download track');
		return;
	}

	info(OK, 'Temporary saved track at '.$file_path);

	fetch_album_cover($track_info_ref->{mp3tags});

	if(write_mp3_tags($file_path, $track_info_ref->{mp3tags}))
	{
		info(INFO, 'MP3 tags added for ' . $file_path);
	}
	else
	{
		info(ERROR, 'Failed to add MP3 tags for ' . $file_path);
	}

	my $target_path = $opt{dir};
	if($opt{path})
	{
		$target_path = File::Spec->catdir($target_path, $track_info_ref->{storage_path});
	}

	my $file_util = File::Util->new();
	if(!-d $file_util->make_dir($target_path => oct DEFAULT_PERMISSIONS => {if_not_exists => 1}))
	{
		info(ERROR, 'Failed to create: ' . $target_path);
		return;
	}

	$target_path = File::Spec->catfile($target_path,  $track_info_ref->{title} . FILE_SAVE_EXT);
	if(rename_track($file_path, $target_path))
	{
		info(INFO, $file_path . ' -> ' . $target_path);
	}
	else
	{
		info(ERROR, $file_path . ' -> ' . $target_path);
	}
}

sub download_track
{
	my ($url) = @_;

	my $request = $ua->head($url);
	if(!$request->is_success)
	{
		info(DEBUG, 'Request failed');
		log_response($request);
		return;
	}

	$whole_file = '';
	$total_size = $request->headers->content_length;

	info(DEBUG, 'File size from header: ' . $total_size);

	$request = $ua->get($url, ':content_cb' => \&progress);
	if(!$request->is_success)
	{
		info(DEBUG, 'Request failed');
		log_response($request);
		return;
	}

	my ($file_handle, $file_path) = File::Temp::tempfile(DIR => $opt{dir});
	return unless $file_handle;

	binmode $file_handle;
	# Autoflush file contents
	select((select($file_handle),$|=1)[0]);
	{
		local $\ = undef;
		print $file_handle $whole_file;
	}

	my $disk_data_size = (stat($file_handle))[7];
	close $file_handle;

	if($total_size && $disk_data_size != $total_size)
	{
		info(DEBUG, 'Actual file size differs from expected ('.$disk_data_size.'/'.$total_size.')');
	}

	return $file_path;
}

sub get_track_url
{
	my $track_info_ref = shift;

	my $album_id = $track_info_ref->{album_id};
	my $track_id = $track_info_ref->{track_id};
	my $is_hq = ($opt{bitrate} && ($opt{bitrate} eq HQ_BITRATE)) ? 1 : 0;
	# Get track path information
	my $request = $ua->get
	(
		$opt{mobile} ?
			MOBILE_YANDEX_BASE.sprintf(MOBILE_DOWNLOAD_INFO_MASK, $track_id)
			:
			YANDEX_BASE.sprintf(DOWNLOAD_INFO_MASK, $track_id, $album_id, time, $is_hq)
	);
	if(!$request->is_success)
	{
		info(DEBUG, 'Request failed');
		log_response($request);
		return;
	}

	my ($json_data) = $request->content;
	if(!$json_data)
	{
		info(DEBUG, 'Can\'t parse JSON blob');
		log_response($request);
		return;
	}

	my $json = create_json($json_data);
	if(!$json)
	{
		info(DEBUG, 'Can\'t create json from data');
		log_response($request);
		return;
	}

	# Pick specified bitrate or highest available
	my $url;
	if($opt{mobile})
	{
		# Sort by available bitrate (highest first)
		@{$json->{result}} = sort { $b->{bitrateInKbps} <=> $a->{bitrateInKbps} } @{$json->{result}};

		my ($idx, $target_idx) = (0, -1);
		for my $track_info(@{$json->{result}})
		{
			if($track_info->{codec} eq DEFAULT_CODEC)
			{
				if($opt{bitrate} && $track_info->{bitrateInKbps} == $opt{bitrate})
				{
					$target_idx = $idx;
					last;
				}
				elsif(!$opt{bitrate})
				{
					$target_idx = $idx;
					last;
				}
			}

			$idx++;
		}

		if($target_idx < 0)
		{
			info(DEBUG, 'Can\'t find track with proper format & bitrate');
			log_response($request);
			return;
		}

		$url = @{$json->{result}}[$target_idx]->{downloadInfoUrl};
	}
	else
	{
		$url = $json->{src};
	}

	$url = 'https:' . $url unless $url =~ /^https:/;
	$request = $ua->get($url);
	if(!$request->is_success)
	{
		info(DEBUG, 'Request failed');
		log_response($request);
		return;
	}

	# No proper XML parsing cause it will break soon
	my %fields = ($request->content =~ /<(\w+)>([^<]+?)<\/\w+>/g);

	my $hash = Digest::MD5::md5_hex(MD5_SALT . substr($fields{path}, 1) . $fields{s});
	$url = sprintf(DOWNLOAD_PATH_MASK, $fields{host}, $hash, $fields{ts}.$fields{path}, $track_id);

	info(DEBUG, 'Track url: ' . $url);

	return $url;
}

sub get_album_tracks_info
{
	my $album_id = shift;

	my $request = $ua->get
	(
		$opt{mobile} ?
			MOBILE_YANDEX_BASE.sprintf(MOBILE_ALBUM_INFO_MASK, $album_id)
			:
			YANDEX_BASE.sprintf(ALBUM_INFO_MASK, $album_id, time)
	);
	if(!$request->is_success)
	{
		info(DEBUG, 'Request failed');
		log_response($request);
		return;
	}


	my ($json_data) = $request->content;
	if(!$json_data)
	{
		info(DEBUG, 'Can\'t parse JSON blob');
		log_response($request);
		return;
	}

	my $json = create_json($json_data);
	if(!$json)
	{
		info(DEBUG, 'Can\'t create json from data: ' . $@);
		log_response($request);
		return;
	}

	# "Rebase" JSON
	$json = $opt{mobile} ? $json->{'result'} : $json;

	my $title = $json->{title};
	if(!$title)
	{
		info(DEBUG, 'Can\'t get album title');
		return;
	}

	info(INFO, 'Album title: ' . $title);
	info(INFO, 'Tracks total: ' . $json->{trackCount});

	if($opt{mobile} && !$json->{availableForMobile})
	{
		info(ERROR, 'Album is not available via Mobile API');
		return;
	}

	my @tracks = ();
	for my $vol(@{$json->{volumes}})
	{
		for my $track(@{$vol})
		{
			if(!$track->{error})
			{
				push @tracks, create_track_entry($track, 0);
			}
		}
	}

	return @tracks;
}

sub get_playlist_tracks_info
{
	my $playlist_id = shift;

	my $request = $ua->get
	(
		$opt{mobile} ?
			MOBILE_YANDEX_BASE.sprintf(MOBILE_PLAYLIST_INFO_MASK, $opt{kind}, $playlist_id)
			:
			YANDEX_BASE.sprintf(PLAYLIST_INFO_MASK, $opt{kind}, $playlist_id)
	);
	if(!$request->is_success)
	{
		info(DEBUG, 'Request failed');
		log_response($request);
		return;
	}

	my ($json_data) = $request->content;
	if(!$json_data)
	{
		info(DEBUG, 'Can\'t parse JSON blob');
		log_response($request);
		return;
	}

	my $json = create_json($json_data);
	if(!$json)
	{
		info(DEBUG, 'Can\'t create json from data: ' . $@);
		log_response($request);
		return;
	}

	my $title =  $opt{mobile}
		?
		( $opt{playlist} == PLAYLIST_LIKE ? PLAYLIST_LIKE_TITLE : $json->{result}->{title} )
		:
		$json->{playlist}->{title};

	if(!$title)
	{
		info(DEBUG, 'Can\'t get playlist title');
		return;
	}

	info(INFO, 'Playlist title: ' . $title);
	info
	(
		INFO,
		'Tracks total: ' .
		(
			$opt{mobile} ?
				$json->{result}->{trackCount}
				:
				$json->{playlist}->{trackCount}
		)
	);

	my @tracks_info;
	my $track_number = 1;

	if(!$opt{mobile} && $json->{playlist}->{trackIds})
	{
		my @playlist_chunks;
		my $tracks_ref = $json->{playlist}->{trackIds};
		my $sign = $json->{authData}->{user}->{sign};

		push @playlist_chunks, [splice @{$tracks_ref}, 0, 150] while @{$tracks_ref};

		for my $chunk(@playlist_chunks)
		{
			$request = $ua->post
			(
				YANDEX_BASE.PLAYLIST_FULL_INFO,
				{
					strict => 'true',
					sign => $sign,
					lang => 'ru',
					experiments => PLAYLIST_REQ_PART,
					entries => join ',', @{$chunk}
				}
			);

			if(!$request->is_success)
			{
				info(DEBUG, 'Request failed');
				log_response($request);
				return;
			}

			$json = create_json($request->content);
			if(!$json)
			{
				info(DEBUG, 'Can\'t create json from data');
				log_response($request);
				return;
			}

			push @tracks_info,
				map
				{
					create_track_entry($_, $track_number++)
				} grep { !$_->{error} } @{ $json };
		}
	}
	else
	{
		@tracks_info = map
		{
			create_track_entry
			(
				$opt{mobile} ?
					$_->{track}
					:
					$_
				, $track_number++
			)
		}
		grep { !$_->{error} }
		@
		{ 
			$opt{mobile} ?
				$json->{result}->{tracks}
				:
				$json->{playlist}->{tracks} 
		};
	}

	return @tracks_info;
}

sub create_track_entry
{
	my ($track_info, $track_number) = @_;

	# Better detection algo?
	my $is_part_of_album = scalar @{$track_info->{albums}} != 0;

	my $is_various;
	if($track_info->{albums}->[0]->{metaType} ne PODCAST_TYPE)
	{
		$is_various =
			scalar @{$track_info->{artists}} > 1
			||
			($is_part_of_album && $track_info->{albums}->[0]->{artists}->[0]->{name} eq GENERIC_COLLECTION)
		;
	}

	# TALB - album title; TPE2 - album artist;
	# APIC - album picture; TYER - year;
	# TIT2 - song title; TPE1 - song artist;
	# TCON - track genre; TRCK - track number
	my %mp3_tags = ();
	# Special case for podcasts
	if($track_info->{albums}->[0]->{metaType} eq PODCAST_TYPE)
	{
		$mp3_tags{TPE1} = $track_info->{albums}->[0]->{title};
	}
	else
	{
		$mp3_tags{TPE1} = join ', ', map { $_->{name} } @{$track_info->{artists}};
	}
	$mp3_tags{TIT2} = $track_info->{title};
	# No track number info in JSON if fetching from anything but album
	if($track_number)
	{
		$mp3_tags{TRCK} = $track_number;
	}
	else
	{
		$mp3_tags{TRCK} = $track_info->{albums}->[0]->{trackPosition}->{index};
	}

	# Append track postfix (like remix) if present
	if(exists $track_info->{version})
	{
		$mp3_tags{TIT2} .= "\x20" . '(' . $track_info->{version} . ')';
	}

	# For deleted tracks
	if($is_part_of_album)
	{
		$mp3_tags{TALB} = $track_info->{albums}->[0]->{title};
		if($track_info->{albums}->[0]->{metaType} eq PODCAST_TYPE)
		{
			$mp3_tags{TPE2} = $mp3_tags{TALB};
		}
		else
		{
			$mp3_tags{TPE2} = $is_various ? GENERIC_TITLE : $track_info->{albums}->[0]->{artists}->[0]->{name};
		}
		# 'Dummy' cover for post-process
		$mp3_tags{APIC} = $track_info->{albums}->[0]->{coverUri};
		$mp3_tags{TYER} = $track_info->{albums}->[0]->{year};
		$mp3_tags{TCON} = $track_info->{albums}->[0]->{genre};
	}

	# Substitute placeholders within a track name and a path name
	my $track_filename = $opt{pattern};
	my $storage_path = $opt{path};
	while (my ($pattern, $tag_id) = each %{&PATTERN_MP3TAGS_RELS})
	{
		$track_filename =~ s/\#$pattern/$mp3_tags{$tag_id}/gi;
		$storage_path =~ s/\#$pattern/$mp3_tags{$tag_id}/gi;
	}

	return
	{
		# Album id
		album_id => $track_info->{albums}->[0]->{id},
		# Track id
		track_id => $track_info->{id},
		# MP3 tags
		mp3tags => \%mp3_tags,
		# 'Save As' file name
		title => $track_filename,
		# 'Save As' directory
		storage_path => $storage_path,
	};
}

sub write_mp3_tags
{
	my ($file_path, $mp3tags) = @_;

	my $mp3 = MP3::Tag->new($file_path);
	if(!$mp3)
	{
		info(DEBUG, 'Can\'t create MP3::Tag object: ' . $@);
		return;
	}

	$mp3->new_tag('ID3v2');

	while(my ($frame, $data) = each %{$mp3tags})
	{
		# Skip empty
		if($data)
		{
			info(DEBUG, 'add_frame: ' . $frame . '=' . substr $data, 0, 16);

			$mp3->{ID3v2}->add_frame
			(
				$frame,
				ref $data eq ref [] ? @{$data} : $data
			);
		}
	}

	$mp3->{ID3v2}->write_tag;
	$mp3->close();

	return 1;
}

sub fetch_album_cover
{
	my $mp3tags = shift;

	my $cover_url = $mp3tags->{APIC};
	if(!$cover_url)
	{
		info(DEBUG, 'Empty cover url');
		return;
	}

	# Normalize url
	$cover_url =~ s/%%/${\(COVER_RESOLUTION)}/;
	$cover_url = 'https://' . $cover_url;

	info(DEBUG, 'Cover url: ' . $cover_url);

	my $request = $ua->get($cover_url);
	if(!$request->is_success)
	{
		info(DEBUG, 'Request failed');
		log_response($request);
		undef $mp3tags->{APIC};
		return;
	}

	$mp3tags->{APIC} = [chr(0x0), 'image/jpg', chr(0x0), 'Cover (front)', $request->content];
}

sub rename_track
{
	my ($src_path, $dst_path) = @_;

	my ($src_fh, $dst_fh, $is_open_success, $errors) = (undef, undef, 1, 0);

	if(IS_WIN)
	{
		# Extend path limit to 32767
		$dst_path = '\\\\?\\' . File::Spec->rel2abs($dst_path);
	}

	for(;;)
	{
		if($errors >= RENAME_ERRORS_MAX)
		{
			info(DEBUG, 'File manipulations failed');
			last;
		}

		if(!$is_open_success)
		{
			close $src_fh if $src_fh;
			close $dst_fh if $dst_fh;
			unlink $src_path if -e $src_path;

			last;
		}

		$is_open_success = open($src_fh, '<', $src_path);
		if(!$is_open_success)
		{
			info(DEBUG, 'Can\'t open src_path: ' . $src_path);
			$errors++;
			redo;
		}

		if(IS_WIN)
		{
			my $unicode_path = Encode::encode('UTF-16LE', $dst_path);
			Encode::_utf8_off($unicode_path);
			$unicode_path .= "\x00\x00";
			# GENERIC_WRITE, OPEN_ALWAYS
			my $native_handle = Win32API::File::CreateFileW($unicode_path, 0x40000000, 0, [], 2, 0, 0);
			# ERROR_ALREADY_EXISTS
			if($^E && $^E != 183)
			{
				info(DEBUG, 'CreateFileW failed with: ' . $^E);
				$errors++;
				redo;
			}

			$is_open_success = Win32API::File::OsFHandleOpen($dst_fh = IO::Handle->new(), $native_handle, 'w');
			if(!$is_open_success)
			{
				info(DEBUG, 'OsFHandleOpen failed with: ' . $!);
				$errors++;
				redo;
			}
		}
		else
		{
			$is_open_success = open($dst_fh, '>', $dst_path);
			if(!$is_open_success)
			{
				info(DEBUG, 'Can\'t open dst_path: ' . $dst_path);
				$errors++;
				redo;
			}
		}

		if(!File::Copy::copy($src_fh, $dst_fh))
		{
			$is_open_success = 0;
			info(DEBUG, 'File::Copy::copy failed with: ' . $!);
			$errors++;
			redo;
		}

		close $src_fh;
		close $dst_fh;

		unlink $src_path;

		return 1;
	}

	return 0;
}

sub create_json
{
	my $json_data = shift;

	my $json;
	eval
	{
		$json = $json_decoder->decode($json_data);
	};

	if($@)
	{
		info(DEBUG, 'Error decoding json ' . $@);
		return;
	}

	HTML::Entities::decode_entities($json_data);

	return $json;
}

sub info
{
	my ($type, $msg) = @_;

	if($opt{silent} && $type ne ERROR)
	{
		 return;
	}

	if($type eq DEBUG)
	{
		return if !$opt{debug};
		# Func, line, msg
		$msg = (caller(1))[3] . "(" . (caller(0))[2] . "): " . $msg;
	}

	if(IS_WIN)
	{
		local $\ = undef;

		my $attr = $main::console->Attr();
		$main::console->Attr($log_colors{$type}->{win});

		print '['.$type.']';

		$main::console->Attr($attr);
		$msg = ' ' . $msg;
	}
	else
	{
		$msg = Term::ANSIColor::colored('['.$type.']', $log_colors{$type}->{nix}) . ' ' . $msg;
	}
	# Actual terminal width detection?
	$msg = sprintf('%-80s', $msg);

	my $out = $type eq ERROR ? *STDERR : *STDOUT;
	print $out $msg;
}

sub progress
{
	my ($data, undef, undef) = @_;

	$whole_file .= $data;
	print progress_bar(length($whole_file), $total_size);
}

sub progress_bar
{
	my ($got, $total, $width, $char) = @_;

	$width ||= 25; $char ||= '=';
	my $num_width = length $total;
	sprintf "|%-${width}s| Got %${num_width}s bytes of %s (%.2f%%)\r", 
		$char x (($width-1) * $got / $total). '>', 
		$got, $total, 100 * $got / +$total;
}

sub read_file
{
	my $filename = shift;

	if(open(my $fh, '<', $filename))
	{
		binmode $fh;
		chomp(my @lines = <$fh>);
		close $fh;

		# Should I just drop this stuff and demand only utf8?
		my $blob = join '', @lines;
		my $decoder = Encode::Guess->guess($blob, 'utf8');
		$decoder = Encode::Guess->guess($blob, 'cp1251') unless ref $decoder;

		if(!ref $decoder)
		{
			info(ERROR, 'Can\'t detect ' . $filename . ' internal encoding');
			return;
		}

		@lines = map($decoder->decode($_), @lines);

		return @lines;
	}

	info(ERROR, 'Failed to open file ' . $opt{ignore});

	return;
}

sub log_response
{
	my $response = shift;
	return if !$opt{debug};

	my $log_filename = RESPONSE_LOG_PREFIX . time;
	if(open(my $fh, '>', $log_filename))
	{
		binmode $fh;
		print $fh $response->as_string;
		close $fh;

		info(DEBUG, 'Response stored at ' . $log_filename);
	}
	else
	{
		info(DEBUG, 'Failed to store response stored at ' . $log_filename);
	}
}

sub print_debug_info
{
	info(DEBUG, 'Yandex Music Downloader v' . VERSION . NL . NL);
	info(DEBUG, 'OS: ' . $^O . '; Path: ' . $^X . '; Version: ' . $^V);
	
	info(DEBUG,  'Cookie: ' . $opt{cookie}) if $opt{cookie};
	info(DEBUG,  'Auth: ' . $opt{auth}) if $opt{auth};
}
