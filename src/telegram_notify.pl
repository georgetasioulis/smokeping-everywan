#!/usr/bin/perl
use strict;
use warnings;
use HTTP::Tiny;
use JSON::PP;
use DBI;
use POSIX qw(strftime);
use Encode qw(decode_utf8);

# Configuration from Environment
my $BOT_TOKEN = $ENV{'TELEGRAM_BOT_TOKEN'};
my $CHAT_ID   = $ENV{'TELEGRAM_CHAT_ID'};

# If no Telegram config, exit silently
exit 0 unless ($BOT_TOKEN && $CHAT_ID);

# Arguments from Smokeping Alert
# alertname, target, losspattern, rtt, hostname
my $alertname = $ARGV[0] // "Unknown Alert";
my $target    = $ARGV[1] // "Unknown Target";
my $loss      = $ARGV[2] // "";
my $rtt       = $ARGV[3] // "";
my $hostname  = $ARGV[4] // "";
my $extra_msg = $ARGV[5] // ""; # Custom message (e.g. from route change)

# Clean up Target Name (remove unnecessary ++ signs if present)
$target =~ s/^\++//;

# Get Traceroute Info
my $traceroute_info = "";
my $last_updated = "";
my $db_path = "/opt/traceroute_history/traceroute_history.db";

if (-e $db_path) {
    eval {
        my $dbh = DBI->connect("dbi:SQLite:dbname=$db_path", "", "", { RaiseError => 1, AutoCommit => 1 });
        # Get the MOST RECENT trace for this target (or similar name)
        # We try exact match first, then partial
        my $sth = $dbh->prepare("SELECT path, timestamp FROM traceroutes WHERE target = ? ORDER BY timestamp DESC LIMIT 1");
        $sth->execute($target);
        my $row = $sth->fetchrow_hashref;
        
        # If not found, try flexible matching (Smokeping target names might differ slightly)
        unless ($row) {
             # Remove spaces or underscores
             my $clean_target = $target;
             $clean_target =~ s/[_ ]/%/g;
             $sth = $dbh->prepare("SELECT path, timestamp FROM traceroutes WHERE target LIKE ? ORDER BY timestamp DESC LIMIT 1");
             $sth->execute('%' . $clean_target . '%');
             $row = $sth->fetchrow_hashref;
        }

        if ($row) {
            my $raw_path = $row->{path};
            $last_updated = strftime("%Y-%m-%d %H:%M:%S", localtime($row->{timestamp}));
            
            # Format route: Decode JSON to make it pretty
            my $hops = decode_json($raw_path);
            if (ref $hops eq 'ARRAY') {
                $traceroute_info .= "\n<b>🛣️ Last Known Route ($last_updated):</b>\n<pre>";
                foreach my $hop (@$hops) {
                    my $id = $hop->{id} // "?";
                    my $ip = $hop->{ip} // "*";
                    $traceroute_info .= "$id. $ip\n";
                }
                $traceroute_info .= "</pre>";
            }
        }
    };
    if ($@) {
        # Silent fail on DB error, just don't add trace info
        # warn "DB Error: $@";
    }
}

# Construct Message (HTML format)
my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
my $status_emoji = ($alertname =~ /down/i || $loss =~ /100%/) ? "🔴" : "⚠️";
$status_emoji = "🟢" if ($alertname =~ /clear/i);

my $message = "$status_emoji <b>SmokePing Alert</b>\n\n";
$message .= "<b>Target:</b> $target\n";
$message .= "<b>Alert:</b> $alertname\n";
$message .= "<b>Time:</b> $timestamp\n";

if ($loss) {
    $message .= "<b>Loss Analysis:</b> $loss\n";
}
if ($rtt) {
    $message .= "<b>Latency:</b> $rtt\n";
}
if ($extra_msg) {
    $message .= "<b>Note:</b> $extra_msg\n";
}

$message .= $traceroute_info if $traceroute_info;

$message .= "\n<a href='http://$hostname/smokeping/?target=$target'>View in SmokePing</a>" if $hostname;

# Send to Telegram
my $ua = HTTP::Tiny->new(timeout => 10);
my $response = $ua->post(
    "https://api.telegram.org/bot$BOT_TOKEN/sendMessage",
    {
        headers => { 'Content-Type' => 'application/json' },
        content => encode_json({
            chat_id => $CHAT_ID,
            text    => $message,
            parse_mode => 'HTML',
            disable_web_page_preview => 1
        })
    }
);

if ($response->{success}) {
    # print "Message sent.\n";
} else {
    # print "Failed to send: $response->{status} $response->{reason}\n";
}
