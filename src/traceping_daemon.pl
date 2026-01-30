#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use POSIX qw(strftime);

# Configuración - Adaptada para Docker
my $dsn = "dbi:SQLite:dbname=/data/traceping.sqlite";
my $config_file = '/config/Targets';
my $interval = $ENV{TRACEPING_INTERVAL} || 300;  # 5 minutos por defecto
my $retention_days = $ENV{TRACEPING_RETENTION_DAYS} || 365;  # 1 año por defecto

# Zona horaria desde variable de entorno o por defecto
my $tz = $ENV{TZ} || 'UTC';
$ENV{TZ} = $tz;
POSIX::tzset();

# Cargar librería de Smokeping (ruta en Docker)
use lib '/usr/lib/smokeping';
eval {
    require Smokeping;
    1;
} or do {
    # Si no está disponible, usar método alternativo
    print strftime("%Y-%m-%d %H:%M:%S", localtime) . " - Warning: Smokeping library not found, using alternative method\n";
};

# Inicializar base de datos si no existe
init_database();

print strftime("%Y-%m-%d %H:%M:%S", localtime) . " - Traceping daemon iniciado (PID: $$)\n";
print "  Config: $config_file\n";
print "  Interval: $interval segundos\n";
print "  Retention: $retention_days días\n";
print "  Timezone: $tz\n";

# Loop principal
while (1) {
    my @targets = load_targets();
    my $count = scalar(@targets);
    print strftime("%Y-%m-%d %H:%M:%S", localtime) . " - Ejecutando traceroutes para $count targets...\n";
    
    foreach my $target (@targets) {
        run_traceroute($target);
    }
    
    # Limpiar registros antiguos
    cleanup_old_records();
    
    print strftime("%Y-%m-%d %H:%M:%S", localtime) . " - Ciclo completado. Esperando $interval segundos...\n";
    sleep($interval);
}

sub init_database {
    my $dbh = DBI->connect($dsn, '', '', { RaiseError => 0, PrintError => 0 });
    if ($dbh) {
        $dbh->do('CREATE TABLE IF NOT EXISTS traceroute_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            target TEXT NOT NULL,
            tracert TEXT,
            timestamp TEXT NOT NULL
        )');
        $dbh->do('CREATE INDEX IF NOT EXISTS idx_target_timestamp ON traceroute_history(target, timestamp)');
        $dbh->disconnect;
    }
}

sub load_targets {
    my @targets;
    
    if (defined &Smokeping::load_cfg) {
        # Método con librería Smokeping
        Smokeping::load_cfg($config_file, 1);
        
        foreach my $group (keys %{$Smokeping::cfg->{'Targets'}}) {
            next unless ref $Smokeping::cfg->{'Targets'}->{$group};
            my $group_hr = $Smokeping::cfg->{'Targets'}->{$group};
            
            foreach my $server (keys %{$group_hr}) {
                next unless ref $group_hr->{$server} && ref $group_hr->{$server} eq 'HASH';
                my $target = "${group}.${server}";
                
                if (!exists $group_hr->{$server}->{'host'}) {
                    foreach my $third (keys %{$group_hr->{$server}}) {
                        next if ref $group_hr->{$server}->{$third} ne 'HASH';
                        next if !exists $group_hr->{$server}->{$third}->{'host'};
                        push @targets, { 
                            target => "${target}.${third}", 
                            host => $group_hr->{$server}->{$third}->{'host'} 
                        };
                    }
                } else {
                    push @targets, { 
                        target => $target, 
                        host => $group_hr->{$server}->{'host'} 
                    };
                }
            }
        }
    } else {
        # Método alternativo: parsear archivo de configuración directamente
        if (open(my $fh, '<', $config_file)) {
            my $current_group = '';
            my $current_server = '';
            while (my $line = <$fh>) {
                chomp $line;
                $line =~ s/#.*$//;  # Eliminar comentarios
                $line =~ s/^\s+|\s+$//g;  # Trim
                next if $line eq '';
                
                if ($line =~ /^\+(\w+)/) {
                    $current_group = $1;
                } elsif ($line =~ /^\+\+(\w+)/) {
                    $current_server = $1;
                } elsif ($line =~ /^\+\+\+(\w+)/) {
                    my $third = $1;
                    # Buscar host en las siguientes líneas
                    my $host = '';
                    while (my $next_line = <$fh>) {
                        chomp $next_line;
                        $next_line =~ s/#.*$//;
                        $next_line =~ s/^\s+|\s+$//g;
                        if ($next_line =~ /^host\s*=\s*(.+)$/i) {
                            $host = $1;
                            last;
                        } elsif ($next_line =~ /^\+/) {
                            seek($fh, -length($next_line) - 1, 1);
                            last;
                        }
                    }
                    if ($host) {
                        push @targets, {
                            target => "${current_group}.${current_server}.${third}",
                            host => $host
                        };
                    }
                } elsif ($line =~ /^host\s*=\s*(.+)$/i && $current_group && $current_server) {
                    push @targets, {
                        target => "${current_group}.${current_server}",
                        host => $1
                    };
                }
            }
            close($fh);
        }
    }
    
    return @targets;
}

sub run_traceroute {
    my ($target) = @_;
    my $host = $target->{host};
    my $name = $target->{target};
    
    # Ejecutar traceroute
    my $result = `/usr/bin/traceroute -w 1 -q 1 -m 20 $host 2>&1`; # Optimizado: 1 sonda, max 20 saltos para velocidad
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
    
    my $dbh = DBI->connect($dsn, '', '', { RaiseError => 0, PrintError => 0 });
    if ($dbh) {
        # 1. Recuperar el último traceroute
        my $last_tracert = "";
        my $sth_check = $dbh->prepare('SELECT tracert FROM traceroute_history WHERE target = ? ORDER BY timestamp DESC LIMIT 1');
        $sth_check->execute($name);
        if (my $row = $sth_check->fetchrow_hashref) {
            $last_tracert = $row->{tracert};
        }
        
        # 2. Insertar el nuevo
        my $sth = $dbh->prepare('INSERT INTO traceroute_history (target, tracert, timestamp) VALUES (?, ?, ?)');
        $sth->execute($name, $result, $timestamp);
        
        # 3. Detectar cambios (Si hay config de telegram y habia ruta previa)
        if ($ENV{'TELEGRAM_BOT_TOKEN'} && $last_tracert && $last_tracert ne $result) {
            # Limpiar timestamps/tiempos del output para evitar falsos positivos por jitter
            # Comparamos solo las IPs/Hosts
            my $clean_old = extract_hops($last_tracert);
            my $clean_new = extract_hops($result);
            
            if ($clean_old ne $clean_new) {
                print "Route change detected for $name\n";
                system("/usr/share/webapps/smokeping/telegram_notify.pl", "Route Change Detected", $name, "", "", $host, "Old Route: $clean_old\nNew Route: $clean_new");
            }
        }
        
        $dbh->disconnect;
    }
}

# Helper para extraer solo los saltos (IPs) y ignorar tiempos
sub extract_hops {
    my $trace = shift;
    my @hops;
    foreach my $line (split /\n/, $trace) {
        if ($line =~ /^\s*(\d+)\s+(.+?)\s+\d+\.\d+ ms/) {
            push @hops, "$1: $2";
        }
    }
    return join(",", @hops);
}

sub cleanup_old_records {
    my $dbh = DBI->connect($dsn, '', '', { RaiseError => 0, PrintError => 0 });
    if ($dbh) {
        my $cutoff = strftime("%Y-%m-%d %H:%M:%S", localtime(time - ($retention_days * 86400)));
        my $sth = $dbh->prepare('DELETE FROM traceroute_history WHERE timestamp < ?');
        $sth->execute($cutoff);
        $dbh->disconnect;
    }
}
