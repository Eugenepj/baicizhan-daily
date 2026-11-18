<#
.SYNOPSIS
    baicizhan-daily word fetcher and Ebbinghaus review ledger.

.DESCRIPTION
    Subcommands:
      token  -Token <t>                    save access_token into config.json
      books                                list every wordbook on the account
      sync                                 pull all wordbooks, merge into the ledger
      plan   [-Date yyyy-MM-dd]            pick today's words, write <date>/plan.json
      detail [-TopicIds 1,2] [-Date ...]   full means + sentences, write <date>/words.json
      mark   [-TopicIds 1,2] -Result known|unknown

    Exit code 2 means a fresh access_token is needed from the user.

    NOTE: this file is deliberately ASCII-only. Windows PowerShell 5.1 reads
    BOM-less script files using the ANSI codepage, which corrupts non-ASCII
    source. User-facing Chinese copy lives in SKILL.md / reference.md instead.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('token', 'books', 'sync', 'plan', 'detail', 'mark')]
    [string]$Command,

    [int[]]$TopicIds,

    [ValidateSet('known', 'unknown')]
    [string]$Result,

    [string]$Token,

    [string]$Date
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12 -bor [Net.ServicePointManager]::SecurityProtocol
} catch { }

$ApiBase  = 'https://www.baicizhan-helper.cn'
# Keep all runtime data on the project drive so automation, inspection, and outputs use one store.
$DataRoot = 'D:\Users\LENOVO\baicizhan-daily'

# Ebbinghaus intervals in days, indexed by stage. Stage 0 is due on the day the
# word was collected, so a fresh word is eligible immediately. Actually
# guaranteeing that yesterday's words ship is the must-have pass in Invoke-Plan,
# not this table: a long backlog of unmarked words would otherwise crowd them out.
$Intervals = @(0, 1, 2, 4, 7, 15, 30, 60)
$MaxStage  = $Intervals.Length - 1

$Defaults = [ordered]@{
    token              = ''
    series_name        = 'English in Six'
    daily_target       = 12
    article_max_words  = 650
    dedup_window_days  = 7
    silence_alert_days = 5
}

# Config keys from earlier versions of the selection algorithm.
$ObsoleteConfigKeys = @('max_daily_words', 'preview_count')

# ---------------------------------------------------------------- file IO

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return $raw | ConvertFrom-Json
}

function Write-JsonFile([string]$Path, $Object) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = $Object | ConvertTo-Json -Depth 12
    # PowerShell 5.1 escapes non-ASCII as \uXXXX. Turn it back into real
    # characters so both the user and the agent can read the file directly.
    $json = [regex]::Replace($json, '\\u([0-9a-fA-F]{4})', {
        param($m) [string][char][int]('0x' + $m.Groups[1].Value)
    })
    $enc = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $json, $enc)
}

function Get-DayFolder([datetime]$Day) {
    return (Join-Path $DataRoot $Day.ToString('yyyy-MM-dd'))
}

function Resolve-Day {
    if ([string]::IsNullOrWhiteSpace($Date)) { return (Get-Date).Date }
    return ([datetime]::ParseExact($Date, 'yyyy-MM-dd', $null)).Date
}

function ConvertTo-Day([string]$Text) {
    return ([datetime]::ParseExact($Text, 'yyyy-MM-dd', $null))
}

function ConvertFrom-UnixTime([double]$Value) {
    # The API returns seconds; tolerate milliseconds just in case.
    if ($Value -gt 1e12) { $Value = $Value / 1000 }
    return [DateTimeOffset]::FromUnixTimeSeconds([long]$Value).ToLocalTime().DateTime
}

# ---------------------------------------------------------------- config / auth

function Get-Config {
    $path = Join-Path $DataRoot 'config.json'
    $cfg = Read-JsonFile $path
    if ($null -eq $cfg) {
        $cfg = [pscustomobject]$Defaults
        Write-JsonFile $path $cfg
        return $cfg
    }
    $dirty = $false
    foreach ($k in $Defaults.Keys) {
        if ($null -eq $cfg.PSObject.Properties[$k]) {
            $cfg | Add-Member -NotePropertyName $k -NotePropertyValue $Defaults[$k]
            $dirty = $true
        }
    }
    foreach ($k in $ObsoleteConfigKeys) {
        if ($null -ne $cfg.PSObject.Properties[$k]) {
            $cfg.PSObject.Properties.Remove($k)
            $dirty = $true
        }
    }
    if ($dirty) { Write-JsonFile $path $cfg }
    return $cfg
}

function Save-Config($Config) {
    Write-JsonFile (Join-Path $DataRoot 'config.json') $Config
}

function Stop-NeedToken([string]$Reason) {
    Write-Output "TOKEN_REQUIRED: $Reason"
    Write-Output ''
    Write-Output 'Ask the user to run this in the baicizhan-helper service worker console:'
    Write-Output ''
    Write-Output "chrome.storage.local.get('auth-storage', r => console.log(JSON.parse(r['auth-storage']).state.token))"
    Write-Output ''
    Write-Output 'Then save it with:  bcz.ps1 token -Token "<pasted token>"'
    Write-Output 'Step-by-step instructions for the user are in reference.md.'
    exit 2
}

function Invoke-Bcz([string]$Path) {
    $cfg = Get-Config
    if ([string]::IsNullOrWhiteSpace($cfg.token)) {
        Stop-NeedToken 'no token in config.json'
    }

    try {
        # Invoke-RestMethod on PowerShell 5.1 decodes the body as ISO-8859-1
        # when Content-Type carries no charset, which mangles every Chinese
        # string this API returns. Decode the raw bytes as UTF-8 instead.
        $web = Invoke-WebRequest -Uri ($ApiBase + $Path) -Method Get `
            -Headers @{ access_token = $cfg.token } -TimeoutSec 20 -UseBasicParsing
        $body = [System.Text.Encoding]::UTF8.GetString($web.RawContentStream.ToArray())
        $resp = $null
        if (-not [string]::IsNullOrWhiteSpace($body)) { $resp = $body | ConvertFrom-Json }
    }
    catch {
        $status = $null
        try { $status = [int]$_.Exception.Response.StatusCode } catch { }
        if ($status -eq 401) { Stop-NeedToken 'HTTP 401, token expired' }
        throw "GET $Path failed: $($_.Exception.Message)"
    }

    if ($null -ne $resp -and $null -ne $resp.PSObject.Properties['code']) {
        if ($resp.code -eq 401) { Stop-NeedToken 'API returned code 401, token expired' }
        if (@(400, 403, 500) -contains $resp.code) {
            throw "GET $Path returned code=$($resp.code): $($resp.message)"
        }
    }
    return $resp.data
}

# ---------------------------------------------------------------- ledger

function Get-Ledger {
    $doc = Read-JsonFile (Join-Path $DataRoot 'ledger.json')
    $map = [ordered]@{}
    if ($null -ne $doc -and $null -ne $doc.words) {
        foreach ($w in @($doc.words)) { $map["$($w.topic_id)"] = $w }
    }
    return $map
}

function Save-Ledger($Map) {
    $words = @($Map.Values | Sort-Object { [int]$_.topic_id })
    $doc = [pscustomobject]@{
        version    = 1
        updated_at = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        word_count = $words.Count
        words      = $words
    }
    Write-JsonFile (Join-Path $DataRoot 'ledger.json') $doc
}

function New-LedgerEntry($Raw, [string]$BookName) {
    $collected = (ConvertFrom-UnixTime ([double]$Raw.created_at)).Date
    $stamp = $collected.ToString('yyyy-MM-dd')
    return [pscustomobject]@{
        topic_id       = [int]$Raw.topic_id
        word           = [string]$Raw.word
        mean           = [string]$Raw.mean
        book_id        = [int]$Raw.book_id
        book_name      = $BookName
        created_at     = [long]$Raw.created_at
        collected_date = $stamp
        audio_us       = [string]$Raw.audio_us
        audio_uk       = [string]$Raw.audio_uk
        stage          = 0
        last_reviewed  = $null
        due_date       = $stamp
        removed        = $false
        history        = @()
    }
}

function Get-ActiveWords($Map) {
    return @($Map.Values | Where-Object { -not $_.removed })
}

# ---------------------------------------------------------------- exposure log

function Get-Exposure {
    $doc = Read-JsonFile (Join-Path $DataRoot 'exposure.json')
    if ($null -eq $doc) { return [pscustomobject]@{ days = @() } }
    if ($null -eq $doc.PSObject.Properties['days']) {
        $doc | Add-Member -NotePropertyName days -NotePropertyValue @()
    }
    return $doc
}

function Set-ExposureForDay([datetime]$Day, [int[]]$Ids) {
    $doc = Get-Exposure
    $key = $Day.ToString('yyyy-MM-dd')
    $kept = @($doc.days | Where-Object { $_.date -ne $key })
    $kept += [pscustomobject]@{ date = $key; topic_ids = @($Ids) }
    $doc.days = @($kept | Sort-Object date)
    Write-JsonFile (Join-Path $DataRoot 'exposure.json') $doc
}

function Get-RecentlyExposedIds([datetime]$Day, [int]$WindowDays) {
    $doc = Get-Exposure
    $from = $Day.AddDays(-$WindowDays)
    $ids = @()
    foreach ($d in @($doc.days)) {
        $dt = [datetime]::MinValue
        if ([datetime]::TryParseExact($d.date, 'yyyy-MM-dd', $null, 'None', [ref]$dt)) {
            if ($dt -ge $from -and $dt -lt $Day) { $ids += @($d.topic_ids) }
        }
    }
    return @($ids | Sort-Object -Unique)
}

# ---------------------------------------------------------------- subcommands

function Invoke-SaveToken {
    if ([string]::IsNullOrWhiteSpace($Token)) {
        throw 'Usage: bcz.ps1 token -Token "<access_token>"'
    }
    $cfg = Get-Config
    $cfg.token = $Token.Trim()
    Save-Config $cfg
    Write-Output "Token saved to $(Join-Path $DataRoot 'config.json')"
}

function Get-Books {
    $data = Invoke-Bcz '/books'
    if ($null -eq $data) { return @() }
    if ($null -ne $data.PSObject.Properties['user_books']) { return @($data.user_books) }
    return @($data)
}

function Invoke-Books {
    $books = Get-Books
    Write-Output "Wordbooks: $($books.Count)"
    foreach ($b in $books) {
        Write-Output ("  [{0}] {1}  {2} words" -f $b.user_book_id, $b.book_name, $b.word_num)
    }
    $total = ($books | Measure-Object -Property word_num -Sum).Sum
    Write-Output "Total: $total words"
}

function Invoke-Sync {
    $books = Get-Books
    $map = Get-Ledger
    $seen = @{}
    $added = 0
    $updated = 0

    foreach ($b in $books) {
        $words = Invoke-Bcz ("/book/{0}/words" -f $b.user_book_id)
        if ($null -eq $words) { continue }
        foreach ($raw in @($words)) {
            $key = "$($raw.topic_id)"
            $seen[$key] = $true
            if ($map.Contains($key)) {
                # Keep review state, refresh only what the API owns.
                $e = $map[$key]
                $e.word      = [string]$raw.word
                $e.mean      = [string]$raw.mean
                $e.book_id   = [int]$raw.book_id
                $e.book_name = [string]$b.book_name
                $e.audio_us  = [string]$raw.audio_us
                $e.audio_uk  = [string]$raw.audio_uk
                if ($e.removed) { $e.removed = $false }
                $updated++
            }
            else {
                $map[$key] = New-LedgerEntry $raw ([string]$b.book_name)
                $added++
            }
        }
    }

    # Words deleted from the wordbooks stay in the ledger but drop out of planning.
    $removed = 0
    foreach ($key in @($map.Keys)) {
        if (-not $seen.ContainsKey($key) -and -not $map[$key].removed) {
            $map[$key].removed = $true
            $removed++
        }
    }

    Save-Ledger $map
    Write-Output ("Books {0}, API words {1}; added {2}, updated {3}, retired {4}" -f `
        $books.Count, $seen.Count, $added, $updated, $removed)
    Write-Output ("Ledger: {0}" -f (Join-Path $DataRoot 'ledger.json'))
}

function Invoke-Plan {
    $day = Resolve-Day
    $cfg = Get-Config
    $map = Get-Ledger
    $active = Get-ActiveWords $map

    if ($active.Count -eq 0) { throw 'Ledger is empty. Run sync first.' }

    $target = [int]$cfg.daily_target
    $yesterday = $day.AddDays(-1).ToString('yyyy-MM-dd')

    # Stage 1: every word collected yesterday ships today, no cap and no sort.
    # These are selected by collection date alone, not by due date, so a word
    # already marked earlier today still shows up.
    $mustHave = @($active |
        Where-Object { $_.collected_date -eq $yesterday } |
        Sort-Object @{ Expression = { [long]$_.created_at } })
    $mustIds = @($mustHave | ForEach-Object { [int]$_.topic_id })

    # Stage 2: fill the rest of the quota from the curve, oldest due date first.
    $dueAll = @($active |
        Where-Object { (ConvertTo-Day $_.due_date) -le $day } |
        Sort-Object `
            @{ Expression = { $_.due_date } }, `
            @{ Expression = { [int]$_.stage } }, `
            @{ Expression = { [long]$_.created_at } })
    $dueRest = @($dueAll | Where-Object { $mustIds -notcontains [int]$_.topic_id })

    $curveQuota = [Math]::Max(0, $target - $mustHave.Count)
    $curveTake = @()
    if ($curveQuota -gt 0) { $curveTake = @($dueRest | Select-Object -First $curveQuota) }
    $deferred = $dueRest.Count - $curveTake.Count

    # Stage 3: the curve ran dry before the quota was met. Pull the
    # closest-to-due words forward as preview. Preview is not a review, so it
    # never touches stage or due_date and never enters mark.
    $takenIds = @($mustIds + @($curveTake | ForEach-Object { [int]$_.topic_id }))
    $shortfall = $target - $takenIds.Count
    $previewFill = @()
    if ($shortfall -gt 0) {
        $pool = @($active |
            Where-Object { $takenIds -notcontains [int]$_.topic_id } |
            Sort-Object `
                @{ Expression = { $_.due_date } }, `
                @{ Expression = { [long]$_.created_at } })
        $exposed = Get-RecentlyExposedIds $day ([int]$cfg.dedup_window_days)
        $previewFill = @($pool |
            Where-Object { $exposed -notcontains [int]$_.topic_id } |
            Select-Object -First $shortfall)

        if ($previewFill.Count -lt $shortfall) {
            # Dedup window emptied the pool; relax it, closest-to-due first.
            $need = $shortfall - $previewFill.Count
            $picked = @($previewFill | ForEach-Object { [int]$_.topic_id })
            $previewFill += @($pool |
                Where-Object { $picked -notcontains [int]$_.topic_id } |
                Select-Object -First $need)
        }
    }

    $lastCollect = @($active | ForEach-Object { ConvertTo-Day $_.collected_date } |
        Sort-Object -Descending | Select-Object -First 1)[0]
    $silenceDays = [int]($day - $lastCollect).TotalDays

    $words = @()
    foreach ($pair in @(
            @{ items = $mustHave;    source = 'new' },
            @{ items = $curveTake;   source = 'curve' },
            @{ items = $previewFill; source = 'preview' })) {
        foreach ($w in @($pair.items)) {
            $words += [pscustomobject]@{
                topic_id       = [int]$w.topic_id
                word           = $w.word
                mean           = $w.mean
                source         = $pair.source
                book_name      = $w.book_name
                collected_date = $w.collected_date
                stage          = [int]$w.stage
                due_date       = $w.due_date
                last_reviewed  = $w.last_reviewed
                review_count   = @($w.history).Count
            }
        }
    }

    # A day can now mix sources, so mode is only a summary; mark reads the
    # explicit id list instead.
    $mode = 'due'
    if ($previewFill.Count -eq $words.Count) { $mode = 'preview' }
    elseif ($previewFill.Count -gt 0) { $mode = 'mixed' }

    $markable = @($words | Where-Object { $_.source -ne 'preview' } |
        ForEach-Object { [int]$_.topic_id })

    $plan = [pscustomobject]@{
        date                = $day.ToString('yyyy-MM-dd')
        mode                = $mode
        word_count          = $words.Count
        daily_target        = $target
        must_have_count     = $mustHave.Count
        curve_count         = $curveTake.Count
        preview_count       = $previewFill.Count
        due_total           = $dueAll.Count
        deferred_count      = $deferred
        ledger_total        = $active.Count
        last_collected      = $lastCollect.ToString('yyyy-MM-dd')
        silence_days        = $silenceDays
        silence_alert       = ($silenceDays -gt [int]$cfg.silence_alert_days)
        dedup_window_days   = [int]$cfg.dedup_window_days
        article_max_words   = [int]$cfg.article_max_words
        markable_topic_ids  = $markable
        words               = $words
    }

    $out = Join-Path (Get-DayFolder $day) 'plan.json'
    Write-JsonFile $out $plan
    Set-ExposureForDay $day @($words | ForEach-Object { [int]$_.topic_id })

    Write-Output ("mode={0}  today={1}/{2}  new={3} curve={4} preview={5}" -f `
        $mode, $words.Count, $target, $mustHave.Count, $curveTake.Count, $previewFill.Count)
    Write-Output ("due_total={0}  deferred={1}  ledger={2}  silence={3}d" -f `
        $dueAll.Count, $deferred, $active.Count, $silenceDays)
    Write-Output ("Words: {0}" -f (($words | ForEach-Object { $_.word }) -join ', '))
    if ($mustHave.Count -gt 0) {
        Write-Output ("Must-have (collected {0}): {1}" -f `
            $yesterday, (($mustHave | ForEach-Object { $_.word }) -join ', '))
    }
    if ($plan.silence_alert) {
        Write-Output ("SILENCE_ALERT: no new words collected for {0} days." -f $silenceDays)
    }
    if ($previewFill.Count -gt 0) {
        Write-Output ("PREVIEW_FILL: {0} words are not due yet; mark will skip them." -f `
            $previewFill.Count)
    }
    if ($words.Count -lt $target) {
        Write-Output ("UNDERFILLED: only {0} words available, target is {1}." -f `
            $words.Count, $target)
    }
    Write-Output ("plan: {0}" -f $out)
}

function Invoke-Detail {
    $day = Resolve-Day
    $ids = $TopicIds

    if (-not $ids -or $ids.Count -eq 0) {
        $planPath = Join-Path (Get-DayFolder $day) 'plan.json'
        $plan = Read-JsonFile $planPath
        if ($null -eq $plan) { throw "No $planPath. Run plan first." }
        $ids = @($plan.words | ForEach-Object { [int]$_.topic_id })
    }

    $map = Get-Ledger
    $results = @()

    foreach ($id in $ids) {
        $path = "/word/{0}?withDict=true&withMedia=false&withSimilarWords=false" -f $id
        $data = Invoke-Bcz $path

        $dict = $null
        if ($null -ne $data) {
            if ($null -ne $data.PSObject.Properties['dict'] -and $null -ne $data.dict) {
                $dict = $data.dict
            }
            elseif ($null -ne $data.PSObject.Properties['dict_wiki'] -and $null -ne $data.dict_wiki) {
                $dict = $data.dict_wiki.dict
            }
        }

        $basic = $null
        if ($null -ne $dict) { $basic = $dict.word_basic_info }
        $entry = $null
        if ($map.Contains("$id")) { $entry = $map["$id"] }

        $word = ''
        if ($null -ne $basic -and $basic.word) { $word = [string]$basic.word }
        elseif ($null -ne $entry) { $word = [string]$entry.word }

        $accentUsa = ''
        $accentUk = ''
        $etyma = ''
        if ($null -ne $basic) {
            $accentUsa = [string]$basic.accent_usa
            $accentUk = [string]$basic.accent_uk
            $etyma = [string]$basic.etyma
        }

        $bookMean = ''
        $collected = ''
        $stage = 0
        $due = ''
        if ($null -ne $entry) {
            $bookMean = [string]$entry.mean
            $collected = [string]$entry.collected_date
            $stage = [int]$entry.stage
            $due = [string]$entry.due_date
        }

        $chnMeans = @()
        $enMeans = @()
        $sentences = @()
        $phrases = @()
        $syn = @()
        $ant = @()
        $exams = @()

        if ($null -ne $dict) {
            foreach ($m in @($dict.chn_means)) {
                if ($null -eq $m) { continue }
                $chnMeans += [pscustomobject]@{ mean_type = $m.mean_type; mean = $m.mean }
            }
            foreach ($m in @($dict.en_means)) {
                if ($null -eq $m) { continue }
                $enMeans += [pscustomobject]@{ mean_type = $m.mean_type; mean = $m.mean }
            }
            foreach ($s in @($dict.sentences)) {
                if ($null -eq $s) { continue }
                $sentences += [pscustomobject]@{
                    sentence         = $s.sentence
                    sentence_trans   = $s.sentence_trans
                    highlight_phrase = $s.highlight_phrase
                }
            }
            foreach ($p in @($dict.short_phrases)) {
                if ($null -eq $p) { continue }
                $phrases += [pscustomobject]@{
                    short_phrase       = $p.short_phrase
                    short_phrase_trans = $p.short_phrase_trans
                }
            }
            foreach ($s in @($dict.synonyms)) {
                if ($null -ne $s) { $syn += [string]$s.syn_ant }
            }
            foreach ($a in @($dict.antonyms)) {
                if ($null -ne $a) { $ant += [string]$a.syn_ant }
            }
            foreach ($x in @($dict.exams)) {
                if ($null -ne $x) { $exams += [string]$x }
            }
        }

        $results += [pscustomobject]@{
            topic_id       = [int]$id
            word           = $word
            accent_usa     = $accentUsa
            accent_uk      = $accentUk
            etyma          = $etyma
            book_mean      = $bookMean
            collected_date = $collected
            stage          = $stage
            due_date       = $due
            chn_means      = $chnMeans
            en_means       = $enMeans
            sentences      = $sentences
            short_phrases  = $phrases
            synonyms       = $syn
            antonyms       = $ant
            exams          = $exams
        }
    }

    $doc = [pscustomobject]@{
        date       = $day.ToString('yyyy-MM-dd')
        word_count = $results.Count
        words      = $results
    }
    $out = Join-Path (Get-DayFolder $day) 'words.json'
    Write-JsonFile $out $doc

    Write-Output ("Fetched {0} words" -f $results.Count)
    foreach ($r in $results) {
        Write-Output ("  {0}  means={1}  sentences={2}  phrases={3}" -f `
            $r.word, @($r.chn_means).Count, @($r.sentences).Count, @($r.short_phrases).Count)
    }
    Write-Output ("words: {0}" -f $out)
}

function Invoke-Mark {
    if ([string]::IsNullOrWhiteSpace($Result)) {
        throw 'Usage: bcz.ps1 mark [-TopicIds 1,2] -Result known|unknown'
    }

    $day = Resolve-Day
    $ids = $TopicIds

    if (-not $ids -or $ids.Count -eq 0) {
        $planPath = Join-Path (Get-DayFolder $day) 'plan.json'
        $plan = Read-JsonFile $planPath
        if ($null -eq $plan) { throw "No $planPath. Pass -TopicIds explicitly." }

        # A day can mix due words with preview filler. Only the due ones count
        # as a review; plans written before this field fall back to source.
        if ($null -ne $plan.PSObject.Properties['markable_topic_ids']) {
            $ids = @($plan.markable_topic_ids | ForEach-Object { [int]$_ })
        }
        else {
            $ids = @($plan.words |
                Where-Object { $_.source -ne 'preview' } |
                ForEach-Object { [int]$_.topic_id })
        }

        $skipped = @($plan.words).Count - $ids.Count
        if ($ids.Count -eq 0) {
            throw "$($plan.date) has no reviewable words; all of them were preview. Pass -TopicIds to override."
        }
        if ($skipped -gt 0) {
            Write-Output ("Skipping {0} preview words; they do not count as a review." -f $skipped)
        }
    }

    $map = Get-Ledger
    $lines = @()

    foreach ($id in $ids) {
        $key = "$id"
        if (-not $map.Contains($key)) {
            $lines += "  skip $id : not in ledger"
            continue
        }
        $e = $map[$key]

        if ($Result -eq 'known') {
            $e.stage = [Math]::Min([int]$e.stage + 1, $MaxStage)
            $due = $day.AddDays($Intervals[[int]$e.stage])
        }
        else {
            $e.stage = 0
            # A forgotten word comes back tomorrow, not on its original
            # collection date, which is already in the past.
            $due = $day.AddDays(1)
        }

        $e.last_reviewed = $day.ToString('yyyy-MM-dd')
        $e.due_date = $due.ToString('yyyy-MM-dd')
        $e.history = @(@($e.history) + @([pscustomobject]@{
            date   = $day.ToString('yyyy-MM-dd')
            result = $Result
            stage  = [int]$e.stage
        }))

        $lines += ("  {0} -> stage {1}, next {2}" -f $e.word, $e.stage, $e.due_date)
    }

    Save-Ledger $map
    Write-Output ("Marked {0}: {1} words" -f $Result, $ids.Count)
    foreach ($l in $lines) { Write-Output $l }
}

# ---------------------------------------------------------------- entry point

if (-not (Test-Path -LiteralPath $DataRoot)) {
    New-Item -ItemType Directory -Path $DataRoot -Force | Out-Null
}

switch ($Command) {
    'token'  { Invoke-SaveToken }
    'books'  { Invoke-Books }
    'sync'   { Invoke-Sync }
    'plan'   { Invoke-Plan }
    'detail' { Invoke-Detail }
    'mark'   { Invoke-Mark }
}
