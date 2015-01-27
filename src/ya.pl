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
    MUSIC_INFO_REGEX => qr/var\s+Mu\s+=\s+(.+?);\s+<\/script>/is,
    DOWNLOAD_INFO_MASK => '/api/v1.5/handlers/api-jsonp.jsx?requestId=2&nc=%d&action=getTrackSrc&p=download-info/%s/2.mp3',
    DOWNLOAD_PATH_MASK => 'http://%s/get-mp3/%s/%s?track-id=%s&from=service-10-track&similarities-experiment=default',
    PLAYLIST_INFO_MASK => '/users/%s/playlists/%d',
    ALBUM_INFO_MASK => '/album/%d',
    FILE_SAVE_EXT => '.mp3',
    ARTIST_TITLE_DELIM => ' - '
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

my ($whole_file, $total_size);
my $ua = LWP::UserAgent->new(agent => AGENT, cookie_jar => new HTTP::Cookies, timeout => TIMEOUT);
my $json_decoder = JSON::PP->new->utf8->pretty->allow_nonref;
$json_decoder->allow_singlequote(1);


if($opt->album || ($opt->playlist && $opt->kind))
{
    my @track_list_info;
    
    if($opt->album)
    {
        info(INFO, 'Fetching album info: '.$opt->album);
        
        @track_list_info = get_album_tracks_info($opt->album);
        
        if($opt->track)
        {
            info(INFO, 'Filtering single track: '.$opt->track.' ['.$opt->album.']');
            @track_list_info = grep
            (
                (split(/\./, $_->{dir}))[1] eq $opt->track
                ,
                @track_list_info
            );
        }
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
        if(!$track_info_ref->{title})
        {
            info(ERROR, 'Track with non-existent title. Skipping...');
            next;
        }
        if(!$track_info_ref->{dir})
        {
            info(ERROR, 'Track with non-existent path (deleted?). Skipping...');
            next;
        }
        
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
    
    my $request = $ua->head($url);
    if(!$request->is_success)
    {
        info(DEBUG, 'HEAD request failed in download_track');
        return;
    }
    
    $whole_file = '';
    $total_size = $request->headers->content_length;
    info(DEBUG, 'File size from header: '.$total_size);
    
    $request = $ua->get($url, ':content_cb' => \&progress);
    if(!$request->is_success)
    {
        info(DEBUG, 'GET request failed in '.(caller(0))[3]);
        return;
    }
    
    my $file_path = $opt->dir.'/'.$title.FILE_SAVE_EXT;
    if(open(F, '>', $file_path))
    {
        local $\ = undef;
        
        binmode F;
        print F $whole_file;
        close F;
        
        my $disk_data_size = -s $file_path;
        
        if($total_size && $disk_data_size != $total_size)
        {
            info(DEBUG, 'Actual file size differs from expected ('.$disk_data_size.'/'.$total_size.')');
        }
    
        return $file_path;
    }
    
    info(DEBUG, 'Failed to open file '.$file_path);
    return;
}

sub get_track_url
{
    my $storage_dir = shift;
    
    my $request = $ua->get(YANDEX_BASE.sprintf(DOWNLOAD_INFO_MASK, time, $storage_dir));
    if(!$request->is_success)
    {
        info(DEBUG, 'Request failed in get_track_url');
        return;
    }
    
    my ($json_data) = ($request->as_string =~ /Ya\.Music\.Jsonp\.callback\(['"]\d+['"],\s*(.+?)\);/);
    if(!$json_data)
    {
        info(DEBUG, 'Can\'t parse JSON blob');
        return;
    }
    
    my $json = create_json($json_data);
    if(!$json)
    {
        info(DEBUG, 'Can\'t create json from data');
        return;
    }
    
    my %fields =
    (
        host => $json->[0]->{host},
        path => $json->[0]->{path},
        ts => $json->[0]->{ts},
        region => $json->[0]->{region},
        s => $json->[0]->{s}
    );
    
    my $hash = hash(substr($fields{path}, 1) . $fields{s});
    
    my $url = sprintf(DOWNLOAD_PATH_MASK, $fields{host}, $hash, $fields{ts}.$fields{path}, (split /\./, $storage_dir)[1]);
    
    info(DEBUG, 'Track url: '.$url);
    
    return $url;
}

sub get_album_tracks_info
{
    my $album_id = shift;
    
    my $request = $ua->get(YANDEX_BASE.sprintf(ALBUM_INFO_MASK, $album_id));
    if(!$request->is_success)
    {
        info(DEBUG, 'Request failed in get_album_tracks_info');
        return;
    }
    
    my ($json_data) = ($request->as_string =~ MUSIC_INFO_REGEX);
    if(!$json_data)
    {
        info(DEBUG, 'Can\'t parse JSON blob');
        return;
    }
    
    my $json = create_json($json_data);
    if(!$json)
    {
        info(DEBUG, 'Can\'t create json from data');
        return;
    }
    
    my $title = $json->{pageData}->{title};
    if(!$title)
    {
        info(DEBUG, 'Can\'t get album title');
        return;
    }

    fix_encoding(\$title);

    info(INFO, 'Album title: '.$title);
    info(INFO, 'Tracks total: '. $json->{pageData}->{trackCount});

    return map
    {
        {
            dir => $_->{storageDir},
            title=> $_->{artists}->[0]->{name} . ARTIST_TITLE_DELIM . $_->{title} 
        }
    } @{ $json->{pageData}->{volumes}->[0] };
}

sub get_playlist_tracks_info
{
    my $playlist_id = shift;
    
    my $request = $ua->get(YANDEX_BASE.sprintf(PLAYLIST_INFO_MASK, $opt->kind, $playlist_id));
    if(!$request->is_success)
    {
        info(DEBUG, 'Request failed in get_playlist_tracks_info');
        return;
    }
    
    my ($json_data) = ($request->as_string =~ MUSIC_INFO_REGEX);
    if(!$json_data)
    {
        info(DEBUG, 'Can\'t parse JSON blob');
        return;
    }
    
    my $json = create_json($json_data);
    if(!$json)
    {
        info(DEBUG, 'Can\'t create json from data');
        return;
    }
    
    my $title = $json->{pageData}->{playlist}->{title};
    if(!$title)
    {
        info(DEBUG, 'Can\'t get playlist title');
        return;
    }
    
    fix_encoding(\$title);
    
    info(INFO, 'Playlist title: '.$title);
    info(INFO, 'Tracks total: '. $json->{pageData}->{playlist}->{trackCount});
    
    return map
    {
        {
            dir => $_->{storageDir},
            title=> $_->{artists}->[0]->{name} . ARTIST_TITLE_DELIM . $_->{title} 
        }
    } @{ $json->{pageData}->{playlist}->{tracks} };
}

sub create_json
{
    my $json_data = shift;
    
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
    
    return $json;
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
    # Actual terminal width detection?
    $msg = Term::ANSIColor::colored('['.$type.']', $log_colors{$type}) . ' ' . $msg;
    $msg .= ' ' x (80 - length($msg) - length($\));
    
    print $msg;
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
