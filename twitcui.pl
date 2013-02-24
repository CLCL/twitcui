#!/usr/bin/perl

use version; our $VERSION = qv('0.0.1');
use strict;
use warnings;
use utf8;
use YAML;
use Term::ReadLine;
binmode STDOUT => ':utf8';

# 初期設定
  
my $ctw  = cuitwitter->new();
my $term = Term::ReadLine->new('twitter client');
my $OUT  = $term->OUT() || *STDOUT;

# キー入力ループ

while( defined( my $cmd = $term->readline($ctw->get_mode().':$ ') ) ) {
  # NULL: lと同じ
  unless ( $cmd ) {
    if ( $ctw->get_mode() eq 'home_timeline') {
      $cmd = 'l';
    } elsif ( $ctw->get_mode() eq 'mentions') {
      $cmd = 'm';
    } elsif ( $ctw->get_mode() eq 'retweets_of_me') {
      $cmd = 'w';
    } else {
      $cmd = 'u';
    }
  }
  # L: home_timeline取得
  if ( $cmd eq 'L') { $ctw->refresh_tl('home_timeline'); };
  # M: mentions取得
  if ( $cmd eq 'M') { $ctw->refresh_tl('mentions'); };
  # M: mentions取得
  if ( $cmd eq 'W') { $ctw->refresh_tl('retweets_of_me'); };
  # U: user_timeline取得
  if ( $cmd eq 'U') { $ctw->refresh_tl('user_timeline'); };
  # l: TL表示
  if ( $cmd =~ m/^l\s*(\d*)[^\d]*(\d*)/ ) {
    $ctw->show_tl('home_timeline', $1, $2);
  };
  # m: 自分宛てツイート表示
  if ( $cmd =~ m/^m\s*(\d*)[^\d]*(\d*)/ ) {
    $ctw->show_tl('mentions', $1, $2);
  };
  # w: リツイートされたものを表示
  if ( $cmd =~ m/^w\s*(\d*)[^\d]*(\d*)/ ) {
    $ctw->show_tl('retweets_of_me', $1, $2);
  };
  # m: 自分のツイート表示
  if ( $cmd =~ m/^u\s*(\d*)[^\d]*(\d*)/ ) {
    $ctw->show_tl('user_timeline', $1, $2);
  };
  # t: ツイート
  if ( $cmd =~ m/^t\s*(.*)/) {
    $ctw->tweet($1);
  };
  # f: リツイート
  if ( $cmd =~ m/^f\s*(\d*)/ ) {
    $ctw->retweet($1);
  };
  # r: リプライ
  if ( $cmd =~ m/^r\s*(\d*)/ ) {
    $ctw->reply($1);
  };
  # d: 削除
  if ( $cmd =~ m/^d\s*(\d*)/ ) {
    $ctw->destroy($1);
  };
  # q: 終了
  if ( $cmd eq 's') { $ctw->check_limit(); };
  # q: 終了
  if ( $cmd eq 'q') { last; };
  # ヒストリに追加
  $term->addhistory($cmd);
}

exit;

package cuitwit;

use strict;
use warnings;
use utf8;
use Net::Twitter;
use Config::Pit;
use File::Spec;
use FindBin::Real;
use YAML;
sub new {
  my $class = shift;
  # Net::Twitter 準備
  my $keys = YAML::LoadFile( File::Spec->catdir( FindBin::Real::Bin(), 'consumer_keys.yaml' ) );
  my $nt  = Net::Twitter->new(
      traits => [qw/API::RESTv1_1 WrapError/],
      #traits => [qw/API::REST WrapError/],
      consumer_key    => $keys->{consumer_key},
      consumer_secret => $keys->{consumer_key_secret},
      ssl => 1,
  );
  my $pit = pit_get( 'twitter.com@CLCLCL' );
  $nt->access_token       ( $pit->{access_token}        );
  $nt->access_token_secret( $pit->{access_token_secret} );
  # 状態記録ファイル名 $datafile
  my $datafile = File::Spec->catdir( FindBin::Real::Bin(), 'tl_save.yaml' );
  # メモリ上の状態記録 $data 
  my $data = {};
  $data = YAML::LoadFile( $datafile ) if -e $datafile;
  # オブジェクトに登録
  my $self = {
    nt       => $nt,
    datafile => $datafile,
    data     => $data,
    @_,
  };
  # bless
  return bless $self, $class;
}

1;

package cuitwitter;

use strict;
use warnings;
use utf8;
use Date::Parse;
use DateTime;
use Encode;
use HTML::Entities;
use Term::ANSIColor qw(:constants);
use Term::ReadKey;
use YAML;
binmode STDOUT => ':utf8';
$Term::ANSIColor::AUTORESET = 1;
use base qw(cuitwit);

# コンストラクタ
sub new {
  my $class = shift;
  # $max_id（tl前回取得時の最大のstatus_idを記録）
  my $max_id = "0";
  # $mentions_id（mentions前回取得時の最大のstatus_idを記録）
  my $mentions_max_id = "0";
  # 現在のタイムライン保持 $tl
  my $timeline = {
    home_timeline  => Home_timeline ->new(),
    mentions       => Mentions      ->new(),
    user_timeline  => User_timeline ->new(),
    retweets_of_me => Retweets_of_me->new(),
  };
  # 現在のmode保持 $mode
  my $mode = 'home_timeline';
  #
  my $range = 5;
  # オブジェクトに登録
  my $self = cuitwit->new(
    mode     => $mode,
    range    => $range,
    timeline => $timeline,
    @_);
  # bless
  return bless $self, $class;
}

sub set_mode {
  my $self = shift;
  my $mode = shift;
  $self->{mode} = $mode;
}

sub get_mode {
  my $self = shift;
  return $self->{mode};
}

sub check_limit {
  my $self = shift;
  my $nt   = $self->{nt};
  my $res  = $nt->rate_limit_status();
  print Dump $res;
}


# d:削除します。引数$order
sub destroy {
  my $self   = shift;
  my $order  = shift;
  my $nt     = $self->{nt};
  my $tlname = $self->get_mode();
  unless ( $order ) {
    my $str = $term->readline('Destroy no.: ');
    unless ( $str ) {
      print RED "削除をキャンセルしました。\n", RESET;
      return;
    }
    ( $order = $str ) =~ s/[^\d]*//g;
  }
  my $tl = $self->{timeline}->{$tlname}->get_tl();
  my $item  = $tl->[ $order - 1 ]; 
  print "$item->{user}->{screen_name} を削除\n";
  my $res = $nt->destroy_status( $item->{id} );
  print decode_utf8( $nt->http_message )."\n";
}

# f:リツイートします。引数$order
sub retweet {
  my $self   = shift;
  my $order  = shift;
  my $nt     = $self->{nt};
  my $tlname = $self->get_mode();
  unless ( $order ) {
    my $str = $term->readline('Retweet no.: ');
    unless ( $str ) {
      print RED "リツイートをキャンセルしました。\n", RESET;
      return;
    }
    ( $order = $str ) =~ s/[^\d]*//g;
  }
  my $tl = $self->{timeline}->{$tlname}->get_tl();
  my $item  = $tl->[ $order - 1 ]; 
  print "$item->{user}->{screen_name} をリツイート\n";
  my $retweet_id = $item->{retweeted_status}->{id} || $item->{id};
  my $res = $nt->retweet( $retweet_id );
  print decode_utf8( $nt->http_message )."\n";
}

# r:リプライします。引数$order
sub reply {
  my $self   = shift;
  my $order  = shift;
  my $nt     = $self->{nt};
  my $tlname = $self->get_mode();
  unless ( $order ) {
    my $str = $term->readline('Reply no.: ');
    unless ( $str ) {
      print RED "リプライをキャンセルしました。\n", CLEAR;
      return;
    }
    ( $order = $str ) =~ s/[^\d]*//g;
  }
  my $tl = $self->{timeline}->{$tlname}->get_tl();
  my $item  = $tl->[ $order - 1 ]; 
  print "$item->{user}->{screen_name} にリプライ\n";
  my $str   = $term->readline('Reply tweet: ');
  unless ( $str ) {
    print RED "リプライをキャンセルしました。", CLEAR,"\n";
    return;
  }
  my $arg;
  $arg->{status} = decode_utf8('@'."$item->{user}->{screen_name} $str");
  $arg->{in_reply_to_status_id} = $item->{id};
  print "$arg->{status}\n";
  print 'length: ' . length($arg->{status}) . "\n";
  my $res = $nt->update( $arg );
  print decode_utf8( $nt->http_message )."\n";
}

# t:ツイートします。引数なし。
sub tweet {
  my $self = shift;
  my $str  = shift;
  my $nt   = $self->{nt};
  unless ( $str ) {
    $str = $term->readline('Tweet: ');
    unless ( $str ) {
      print RED "ツイートをキャンセルしました。\n", RESET;
      return;
    }
  }
  my $arg;
  $arg->{status} = decode_utf8($str);
  print "$arg->{status}\n";
  print 'length: ' . length($arg->{status}) . "\n";
  my $res = $nt->update( $arg );
  print decode_utf8( $nt->http_message )."\n";
}

# g:タイムライン取得します。引数$tlname、ない場合はいまのモードのTLを取得。
sub refresh_tl {
  my $self   = shift;
  my $tlname = shift || $self->get_mode();
  $self->set_mode($tlname);
  my $nt   = $self->{nt};
  $self->{timeline}->{$tlname}->set_cursor(1);
  $self->{timeline}->{$tlname}->fetch_and_set_tl();
  print "新着：" . $self->{timeline}->{$tlname}->get_count() . "件\n";
}

# l: home_timeline表示、m:mentions表示
sub show_tl {
  my $self   = shift;
  my $tlname = shift;
  my $from   = shift;
  my $to     = shift;
  $self->set_mode($tlname);
  if ( $from && $to ) {
    $self->{range} = $to - $from + 1;
  }
  elsif ( $from && !$to ) {
    $to = $from + $self->{range};
  }
  elsif (!$from && !$to ) {
    $from = $self->{timeline}->{$tlname}->get_cursor();
    $to   = $from + $self->{range};
  }
  # TL未取得なら、取得する
  my $tl = $self->{timeline}->{$tlname}->get_tl();
  $self->refresh_tl() unless ( $tl );
  $self->{timeline}->{$tlname}->set_cursor( $to + 1 );
  $tl = $self->{timeline}->{$tlname}->get_tl();
  $to = scalar( @$tl ) if $to > scalar( @$tl );
  (my $wchar, my $hchar, my $wpixels, my $hpixels) = eval{GetTerminalSize()};
  $wchar = 30 unless $wchar;
  print CLEAR '=' x $wchar ,"\n";
  for ( my $i = $from -1; $i < $to;  $i++ ) {
    my $item = $tl->[$i];
    _printitem($i, $item);
  }
}

sub _printitem {
  my $i = shift;
  my $item = shift;
  my $t = str2time($item->{created_at});
  my $dt = DateTime->from_epoch(epoch => $t)->set_time_zone('Asia/Tokyo');
  (my $wchar, my $hchar, my $wpixels, my $hpixels) = eval{GetTerminalSize()};
  $wchar = 30 unless $wchar;
  my $p = $item->{past};
  if ($item->{retweeted_status} ) {
    print "".($p?BLUE:CLEAR) . ( $i + 1 ) . ". ";
    if ($p) {
      print BOLD BLUE "RT ".$item->{retweeted_status}->{user}->{screen_name}, CLEAR;
    } else {
      print BOLD CYAN "RT ".$item->{retweeted_status}->{user}->{screen_name}, CLEAR;
    }
    if ( $item->{retweet_count} ) {
      print "".($p?BLUE:CLEAR)." $item->{user}->{screen_name}を含めた$item->{retweet_count}人がリツイート";
    }
    print "\n";
    print "".($p?BLUE:CYAN).decode_entities("$item->{retweeted_status}->{text}");
    print "\n";
    if ($p) {
      print BLUE "$dt ";
    } else {
      print      "$dt ";
    }
    print "".($p?BLUE:RED). "twitter.com/$item->{user}->{screen_name}/status/$item->{id}";
    print "\n";
    print "".($p?BLUE:CLEAR). '-' x $wchar ,CLEAR,"\n";
  } 
  else {
    print "".($p?BLUE:CLEAR) . ( $i + 1 ) . ". ";
    if ($p) {
      print BOLD BLUE   $item->{user}->{screen_name}, CLEAR;
    } else {
      print BOLD YELLOW $item->{user}->{screen_name}, CLEAR;
    }
    if ( $item->{retweet_count} ) {
      print "".($p?BLUE:CLEAR)." $item->{user}->{screen_name}を含めた$item->{retweet_count}人がリツイート";
    }
    print "\n";
    print "".($p?BLUE:CLEAR).decode_entities("$item->{text}");
    print "\n";
    if ($p) {
      print BLUE "$dt ";
    } else {
      print      "$dt ";
    }
    print "".($p?BLUE:RED). "twitter.com/$item->{user}->{screen_name}/status/$item->{id}";
    print "\n";
    print "".($p?BLUE:CLEAR). '-' x $wchar ,CLEAR,"\n";
  }
}

1;

package Home_timeline;

use strict;
use warnings;
use utf8;
use base qw(cuitwit);

sub new {
  my $class = shift;
  my $max_id = "0";
  my $tl;
  my $tlname = 'home_timeline';
  my $cursor = 1;
  my $self = cuitwit->new(
    max_id => $max_id,
    tl     => $tl,
    tlname => $tlname,
    cursor => $cursor,
    @_,
  );
  # bless
  return bless $self, $class;
}

sub fetch_tl {
  my $self = shift;
  return $self->{nt}->home_timeline({count => 200});
}

sub get_tl {
  my $self = shift;
  return $self->{tl};
}

sub set_tl {
  my $self = shift;
  my $tl   = shift;
  $self->{tl} = $tl;
  $self->{data} = YAML::LoadFile( $self->{datafile} ) if -e $self->{datafile};
  $self->{count} = 0;
  map {
    # 取得済み範囲$max_idの更新
    if ($_->{id} > $self->{max_id}) {
      $self->{max_id} = $_->{id};
    }
    # 取得済みポストのフラグpastを付ける
    unless ($_->{id} > $self->{data}->{$self->{tlname}}->{max_id} ) {
      $_->{past} = 1;
    } else {
      $self->{count}++;
    }
  } @{$self->{tl}};
  if ( $self->{count} ) {
    $self->{data}->{$self->{tlname}}->{max_id} = $self->{max_id};
    YAML::DumpFile( $self->{datafile}, $self->{data} );
  }
}

sub fetch_and_set_tl {
  my $self = shift;
  $self->set_tl( $self->fetch_tl() );
}

sub get_count{
  my $self = shift;
  return $self->{count};
}

sub get_cursor {
  my $self = shift;
  return $self->{cursor};
}

sub set_cursor {
  my $self = shift;
  my $cursor = shift;
  $self->{cursor} = $cursor;
}

1;

package Mentions;

use strict;
use warnings;
use utf8;

use base "Home_timeline";

sub new {
  my $class  = shift;
  my $tlname = 'mentions';
  my $self   = Home_timeline->new(
    tlname => $tlname,
    @_,
  );
  # bless
  return bless $self, $class;
}

sub fetch_tl {
  my $self = shift;
  return $self->{nt}->mentions();
}

1;

package User_timeline;

use strict;
use warnings;
use utf8;

use base "Home_timeline";

sub new {
  my $class  = shift;
  my $tlname = 'user_timeline';
  my $self   = Home_timeline->new(
    tlname => $tlname,
    @_,
  );
  # bless
  return bless $self, $class;
}

sub fetch_tl {
  my $self = shift;
  return $self->{nt}->user_timeline({count => 200});
}

1;

package Retweets_of_me;

use strict;
use warnings;
use utf8;

use base "Home_timeline";

sub new {
  my $class  = shift;
  my $tlname = 'retweets_of_me';
  my $self   = Home_timeline->new(
    tlname => $tlname,
    @_,
  );
  # bless
  return bless $self, $class;
}

sub fetch_tl {
  my $self = shift;
  return $self->{nt}->retweets_of_me();
}

1;

__END__
