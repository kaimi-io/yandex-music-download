use strict;
use warnings;
use Encode qw/from_to/;
use File::Basename;
use POSIX qw/strftime/;
use YaHash;

use constant IS_WIN => $^O eq 'MSWin32';
use constant
{
    NL => IS_WIN ? "\015\012" : "\012",
    TARGET_ENC => IS_WIN ? 'cp1251' : 'utf8',
    TIMEOUT => 5,
    AGENT => 'Mozilla/5.0 (Windows NT 6.1; WOW64; rv:25.0) Gecko/20100101 Firefox/25.0',
    YANDEX_BASE => 'http://music.yandex.ru',
    TRACK_URI_MASK => '/fragment/track/%d/album/%d?prefix=%s',
    DOWNLOAD_INFO_MASK => '/xml/storage-proxy.xml?p=download-info/%s/2.mp3&nc=%d',
    DOWNLOAD_PATH_MASK => 'http://%s/get-mp3/%s/%s?track-id=%s&from=service-10-track&similarities-experiment=default',
    PLAYLIST_INFO_MASK => '/get/playlist2.xml?kinds=%d&owner=%s&r=%d',
    PLAYLIST_TRACK_INFO_MASK => '/get/tracks.xml?tracks=%s',
    ALBUM_INFO_MASK => '/fragment/album/%d?prefix=%s',
    FILE_SAVE_EXT => '.mp3',
    ARTIST_TITLE_DELIM => ' - ',
    FACEGEN => POSIX::strftime('facegen-%Y-%m-%dT00-00-00', localtime)
};
use constant
{
    DEBUG => 'DEBUG',
    ERROR => 'ERROR',
    INFO => 'INFO',
    OK => 'OK'
};

my %log_colors = 
(
    &DEBUG => 'red on_white',
    &ERROR => 'red',
    &INFO => 'blue on_white',
    &OK => 'green on_white'
);

my %req_modules = 
(
    NIX => [],
    WIN => [ qw/Win32::Console::ANSI/ ],
    ALL => [ qw/JSON::PP Getopt::Long::Descriptive Term::ANSIColor LWP::UserAgent HTTP::Cookies HTML::Entities/ ]
);

$\ = NL;

my @missing_modules;
for(@{$req_modules{ALL}}, IS_WIN ? @{$req_modules{WIN}} : @{$req_modules{NIX}})
{
    eval "require $_";
    if($@)
    {
        ($_) = $@ =~ /locate (.+?)(?:\.pm)? in \@INC/;
        $_ =~ s/\//::/g;
        push @missing_modules, $_;
    }
}

if(@missing_modules)
{
    print 'Please, install this modules: '.join ', ', @missing_modules;
    exit;
}

my ($opt, $usage) = Getopt::Long::Descriptive::describe_options
(
    basename(__FILE__).' %o',
    ['playlist|p:i',    'playlist id to download'],
    ['kind|k:s',        'playlist kind (eg. ya-playlist, music-blog, music-partners, etc.)'],
    ['album|a:i',       'album to download'],
    ['track|t:i',       'track to download (album id must be specified)'],
    ['dir|d:s',         'download path (current direcotry will be used by default)', {default => '.'}],
    [],
    ['debug',           'print debug info during work'],
    ['help',            'print usage'],
    [],
    ['Example: '],
    ["\t".basename(__FILE__).' -p 123 -k ya-playlist'],
    ["\t".basename(__FILE__).' -a 123'],
    ["\t".basename(__FILE__).' -a 123 -t 321']
);

if( $opt->help || ( !($opt->track && $opt->album) && !$opt->album && !($opt->playlist && $opt->kind) )  )
{
    print $usage->text;
    exit;
}

if($opt->dir && !-d $opt->dir)
{
    info(ERROR, 'Please, specify an existing directory');
    exit;
}

my $ua = LWP::UserAgent->new(agent => AGENT, cookie_jar => new HTTP::Cookies, timeout => TIMEOUT);
my $json_decoder = JSON::PP->new->utf8->pretty->allow_nonref;
$json_decoder->allow_singlequote(1);


if($opt->album || ($opt->playlist && $opt->kind))
{
    my @track_list_info;
    
    if($opt->track && $opt->album)
    {
        info(INFO, 'Fetching track info: '.$opt->track.' ['.$opt->album.']');
        
        @track_list_info = get_single_track_info($opt->album, $opt->track);
    }
    elsif($opt->album)
    {
        info(INFO, 'Fetching album info: '.$opt->album);
        
        @track_list_info = get_album_tracks_info($opt->album);
    }
    else
    {
        info(INFO, 'Fetching playlist info: '.$opt->playlist.' ['.$opt->kind.']');
        
        @track_list_info = get_playlist_tracks_info($opt->playlist);
    }
    
    
    if(!@track_list_info)
    {
        info(ERROR, 'Can\'t get track list info');
        exit;
    }
    
    for my $track_info_ref(@track_list_info)
    {
        fetch_track($track_info_ref);
    }
}

sub fetch_track
{
    my $track_info_ref = shift;
    
    fix_encoding(\$track_info_ref->{title});
    $track_info_ref->{title} =~ s/\s+$//;
    $track_info_ref->{title} =~ s/[\\\/:"*?<>|]+/-/g;
    
    info(INFO, 'Trying to fetch track: '.$track_info_ref->{title});
    
    my $track_url = get_track_url($track_info_ref->{dir});
    if(!$track_url)
    {
        info(ERROR, 'Can\'t get track url');
        return;
    }
    
    my $file_path = download_track($track_url, $track_info_ref->{title});
    if(!$file_path)
    {
        info(ERROR, 'Failed to download track');
        return;
    }
    
    info(OK, 'Saved track at '.$file_path);
}


sub download_track
{
    my ($url, $title) = @_;
    
    my $request = $ua->get($url);
    if(!$request->is_success)
    {
        info(DEBUG, 'Request failed in download_track');
        return;
    }
    
    my $web_data_size = $request->headers->{'content-length'};
    
    my $file_path = $opt->dir.'/'.$title.FILE_SAVE_EXT;
    if(open(F, '>', $file_path))
    {
        # Awkward moment
        undef $\;
        
        binmode F;
        print F $request->content;
        close F;
        
        $\ = NL;
        
        my $disk_data_size = -s $file_path;
        
        if($web_data_size && $disk_data_size != $web_data_size)
        {
            info(DEBUG, 'Actual file size differs from expected ('.$disk_data_size.'/'.$web_data_size.')');
        }
    
        return $file_path;
    }
    
    info(DEBUG, 'Failed to open file '.$file_path);
    return;
}

sub get_track_url
{
    my $storage_dir = shift;
    
    my $request = $ua->get(YANDEX_BASE.sprintf(DOWNLOAD_INFO_MASK, $storage_dir, time));
    if(!$request->is_success)
    {
        info(DEBUG, 'Request failed in get_track_url');
        return;
    }
    
    my %fields = (host => '', path => '', ts => '', region => '', s => '');
    
    for my $key(keys %fields)
    {
        if($request->as_string =~ /<$key>(.+?)<\/$key>/)
        {
            $fields{$key} = $1;
        }
        else
        {
            info(DEBUG, 'Failed to parse '.$key);
            return;
        }
    }
    
    my $hash = hash(substr($fields{path}, 1) . $fields{s});
    
    my $url = sprintf(DOWNLOAD_PATH_MASK, $fields{host}, $hash, $fields{ts}.$fields{path}, (split /\./, $storage_dir)[1]);
    
    info(DEBUG, 'Track url: '.$url);
    
    return $url;
}

sub get_single_track_info
{
    my ($album_id, $track_id) = @_;
    
    my $request = $ua->get(YANDEX_BASE.sprintf(TRACK_URI_MASK, $track_id, $album_id, FACEGEN));
    if(!$request->is_success)
    {
        info(DEBUG, 'Request failed in get_single_track_info');
        return;
    }
    
    my ($json_data) = ($request->as_string =~ /data-from="track" onclick=["']return (.+?)["']>/);
    if(!$json_data)
    {
        info(DEBUG, 'Can\'t parse JSON blob');
        return;
    }
    
    HTML::Entities::decode_entities($json_data);
    
    my $json;
    eval
    {
        $json = $json_decoder->decode($json_data);
    };
    
    if($@)
    {
        info(DEBUG, 'Error decoding json '.$@);
        return;
    }
    
    return {dir => $json->{storage_dir}, title => $json->{artist}.ARTIST_TITLE_DELIM.$json->{title}};
}

sub get_album_tracks_info
{
    my $album_id = shift;
    
    my $request = $ua->get(YANDEX_BASE.sprintf(ALBUM_INFO_MASK, $album_id, FACEGEN));
    if(!$request->is_success)
    {
        info(DEBUG, 'Request failed in get_album_tracks_info');
        return;
    } 
    
    my ($json_data) = ($request->as_string =~ /data-from="album-whole" onclick="return (.+?)"><a/);
    if(!$json_data)
    {
        info(DEBUG, 'Can\'t parse JSON blob');
        return;
    }
    
    HTML::Entities::decode_entities($json_data);
    
    my $json;
    eval
    {
        $json = $json_decoder->decode($json_data);
    };
    
    if($@)
    {
        info(DEBUG, 'Error decoding json '.$@);
        return;
    }
    
    
    my $title = $json->{title};
    if(!$title)
    {
        info(DEBUG, 'Can\'t get album title');
        return;
    }
    
    fix_encoding(\$title);
    
    info(INFO, 'Album title: '.$title);
    info(INFO, 'Tracks total: '. $json->{track_count});
    
    
    return map { { dir => $_->{storage_dir}, title=> $_->{artist}.ARTIST_TITLE_DELIM.$_->{title} } } @{$json->{tracks}};
}

sub get_playlist_tracks_info
{
    my $playlist_id = shift;
    
    my $request = $ua->get(YANDEX_BASE.sprintf(PLAYLIST_INFO_MASK, $playlist_id, $opt->kind, time));
    if(!$request->is_success)
    {
        info(DEBUG, 'Request failed in get_playlist_tracks_info');
        return;
    }
    
    my $json_data = $request->content;
    
    HTML::Entities::decode_entities($json_data);
    
    my $json;
    eval
    {
        $json = $json_decoder->decode($json_data);
    };
    
    if($@)
    {
        info(DEBUG, 'Error decoding json '.$@);
        return;
    }
    
    
    my $title = $json->{playlists}[0]->{title};
    if(!$title)
    {
        info(DEBUG, 'Can\'t get playlist title');
        return;
    }
    
    fix_encoding(\$title);
    
    info(INFO, 'Playlist title: '.$title);
    info(INFO, 'Tracks total: '. scalar @{$json->{playlists}[0]->{tracks}});
    
    
    $request = $ua->get(YANDEX_BASE.sprintf(PLAYLIST_TRACK_INFO_MASK, join(',', @{$json->{playlists}[0]->{tracks}})));
    if(!$request->is_success)
    {
        info(DEBUG, 'Request failed in get_playlist_tracks_info');
        return;
    }
    
    eval
    {
        $json = $json_decoder->decode($request->content);
    };
    
    if($@)
    {
        info(DEBUG, 'Error decoding json '.$@);
        return;
    }
    
    
    return map { { dir => $_->{storage_dir}, title=> $_->{artist}.ARTIST_TITLE_DELIM.$_->{title} } } @{$json->{tracks}};
}

sub fix_encoding
{
    my $ref = shift;
    from_to($$ref, 'unicode', TARGET_ENC);
}

sub info
{
    my ($type, $msg) = @_;
    
    return if !$opt->debug && $type eq DEBUG;
    
    print Term::ANSIColor::colored('['.$type.']', $log_colors{$type}), ' ', $msg;
}
