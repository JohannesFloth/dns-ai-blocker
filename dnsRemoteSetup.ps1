
# ============================================================
# DNS-Set-Script fuer Pruefungen - Version 2
# ============================================================

$PruefungsDNS = "10.88.0.50"

Clear-Host

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Herzlich Willkommen zum DNS-Set-Script" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# Modus auswaehlen
# ------------------------------------------------------------

$antwort = Read-Host "Wollen Sie PCs in den Pruefungsmodus versetzen? (J/N)"

if ($antwort -match '^(j|ja)$') {
    $modus = "Setzen"
}
else {
    $antwort = Read-Host "Wollen Sie die PCs zurueck setzen? (J/N)"

    if ($antwort -match '^(j|ja)$') {
        $modus = "Zuruecksetzen"
    }
    else {
        Write-Host "Vorgang abgebrochen." -ForegroundColor Yellow
        return
    }
}

# ------------------------------------------------------------
# Raumnummer und PC-Bereich abfragen
# ------------------------------------------------------------

do {
    $raum = Read-Host "Bitte vierstellige Raumnummer eingeben"
} until ($raum -match '^\d{4}[a-z]+$')

do {
    $eingabe = Read-Host "Startnummer des PCs (01-32)"
} until (
    $eingabe -match '^\d{1,2}$' -and
    [int]$eingabe -ge 1 -and
    [int]$eingabe -le 32
)

$start = [int]$eingabe

do {
    $eingabe = Read-Host "Endnummer des PCs ($start-32)"
} until (
    $eingabe -match '^\d{1,2}$' -and
    [int]$eingabe -ge $start -and
    [int]$eingabe -le 32
)

$ende = [int]$eingabe

# ------------------------------------------------------------
# Hostnamen generieren
# ------------------------------------------------------------

$pcs = @(
    for ($i = $start; $i -le $ende; $i++) {
        "{0}PC{1:D2}" -f $raum, $i
    }
)

Write-Host ""
Write-Host "---------------------------------------------"
Write-Host "Modus:  $modus" -ForegroundColor Cyan
Write-Host "Raum:   $raum"
Write-Host "PCs:    $($pcs -join ', ')"
Write-Host "DNS:    $PruefungsDNS"
Write-Host "---------------------------------------------"
Write-Host ""

$bestaetigung = Read-Host "Konfiguration jetzt ausfuehren? (J/N)"

if ($bestaetigung -notmatch '^(j|ja)$') {
    Write-Host "Vorgang abgebrochen." -ForegroundColor Yellow
    return
}

# ------------------------------------------------------------
# Remote-Konfiguration
# ------------------------------------------------------------

$ergebnisse = @()

foreach ($pc in $pcs) {

    Write-Host ""
    Write-Host "Bearbeite $pc ..." -ForegroundColor Cyan

    try {

        $resultat = Invoke-Command `
            -ComputerName $pc `
            -ArgumentList $modus, $PruefungsDNS `
            -ErrorAction Stop `
            -ScriptBlock {

                param($modus, $dnsServer)

                # Physische Ethernet- und WLAN-Adapter ermitteln.
                # Interface-Typen:
                # 6  = Ethernet
                # 71 = WLAN (IEEE 802.11)

                $adapter = @(
                    Get-NetAdapter -Physical -ErrorAction Stop |
                        Where-Object {
                            $_.NdisPhysicalMedium -in @(0, 9) -or
                            $_.InterfaceName -match
                                'Ethernet|Wi-Fi|Wireless|WLAN|802\.11'
                        }
                )

                if ($adapter.Count -eq 0) {
                    throw "Keine Ethernet- oder WLAN-Adapter gefunden."
                }

                $ausgabe = @()

                foreach ($nic in $adapter) {

                    try {

                        if ($modus -eq "Setzen") {

                            # Pruefungs-DNS fuer IPv4 setzen
                            Set-DnsClientServerAddress `
                                -InterfaceIndex $nic.ifIndex `
                                -ServerAddresses $dnsServer `
                                -ErrorAction Stop
                        }
                        else {

                            # DNS auf automatische Konfiguration
                            # zuruecksetzen
                            Set-DnsClientServerAddress `
                                -InterfaceIndex $nic.ifIndex `
                                -ResetServerAddresses `
                                -ErrorAction Stop
                        }

                        # Aktuelle DNS-Konfiguration auslesen
                        $dns = Get-DnsClientServerAddress `
                            -InterfaceIndex $nic.ifIndex `
                            -AddressFamily IPv4 `
                            -ErrorAction Stop

                        $ausgabe += [PSCustomObject]@{
                            Computer  = $env:COMPUTERNAME
                            Interface = $nic.Name
                            Status    = "OK"
                            DNS       = ($dns.ServerAddresses -join ", ")
                        }
                    }
                    catch {

                        $ausgabe += [PSCustomObject]@{
                            Computer  = $env:COMPUTERNAME
                            Interface = $nic.Name
                            Status    = "FEHLER"
                            DNS       = $_.Exception.Message
                        }
                    }
                }

                Clear-DnsClientCache -ErrorAction Stop

                return $ausgabe
            }

        foreach ($eintrag in $resultat) {

            if ($eintrag.Status -eq "OK") {

                Write-Host (
                    "[OK] {0}: {1} -> {2}" -f
                    $pc, $eintrag.Interface, $eintrag.DNS
                ) -ForegroundColor Green
            }
            else {

                Write-Host (
                    "[FEHLER] {0}: {1} -> {2}" -f
                    $pc, $eintrag.Interface, $eintrag.DNS
                ) -ForegroundColor Red
            }

            $ergebnisse += $eintrag
        }
    }
    catch {

        Write-Host "[FEHLER] ${pc}: $($_.Exception.Message)" `
            -ForegroundColor Red

        $ergebnisse += [PSCustomObject]@{
            Computer  = $pc
            Interface = "-"
            Status    = "FEHLER"
            DNS       = $_.Exception.Message
        }
    }
}

# ------------------------------------------------------------
# Zusammenfassung
# ------------------------------------------------------------

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Zusammenfassung" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$ergebnisse |
    Format-Table Computer, Interface, Status, DNS -AutoSize

$erfolgreich = @(
    $ergebnisse | Where-Object { $_.Status -eq "OK" }
).Count

$fehler = @(
    $ergebnisse | Where-Object { $_.Status -eq "FEHLER" }
).Count

Write-Host ""
Write-Host "Erfolgreiche Interface-Konfigurationen: $erfolgreich" `
    -ForegroundColor Green

Write-Host "Fehlgeschlagene Interface-Konfigurationen: $fehler" `
    -ForegroundColor $(if ($fehler -gt 0) { "Red" } else { "Green" })

Write-Host ""
Write-Host "Bearbeitung abgeschlossen." -ForegroundColor Cyan
