#!/bin/bash

torrentclientname="Qbit"
usenetclientname="SABnzbd"
xseed_host="cross-seed"
xseed_port="2468"
log_file="/config/xseed_db.log"
d="/config/debug_xseed_db.log"

# Create the log file if it doesn't exist
[ ! -f "$d" ] && touch "$d"
echo "clientID: $clientID" >> "$d"

# Determine app and set variables
if [ -n "$radarr_eventtype" ]; then
    app="radarr"
    clientID="$radarr_download_client"
    downloadID="$radarr_download_id"
    filePath="$radarr_moviefile_path"
    eventType="$radarr_eventtype"
elif [ -n "$sonarr_eventtype" ]; then
    app="sonarr"
    clientID="$sonarr_download_client"
    downloadID="$sonarr_download_id"
    filePath="$sonarr_series_path"
    folderPath="$sonarr_episodefile_sourcefolder"
    eventType="$sonarr_eventtype"
elif [ -n "$Lidarr_EventType" ]; then
    app="lidarr"
    clientID="$lidarr_Download_Client"
    filePath="$lidarr_Artist_Path"
    downloadID="$lidarr_Download_Id"
    eventType="$lidarr_EventType"
else
    echo "|WARN| Unknown Event Type. Failing." >> "$d"
    exit 1
fi
echo "$app detected with event type $eventType" >> "$d"

# Function to send request to cross-seed
cross_seed_request() {
    local endpoint="$1"
    local data="$2"
    curl --silent --output /dev/null --write-out "%{http_code}" -X POST "http://$xseed_host:$xseed_port/api/$endpoint?apikey=7f615bcded8877bd166a8edebcf713f2ecd4259e6f34c3bf" --data-urlencode "$data"
}

# Create the log file if it doesn't exist
[ ! -f "$log_file" ] && touch "$log_file"

# Check if the downloadID exists in the log file
unique_id="${downloadID}-${clientID}"
grep -qF "$unique_id" "$log_file" && echo "UniqueDownloadID $unique_id has already been processed. Skipping..." >> "$d" && exit 0

# Handle Unknown Event Type
[ -z "$eventType" ] && echo "|WARN| Unknown Event Type. Failing." >> "$d" && exit 1

# Handle Test Event
[ "$eventType" == "Test" ] && echo "Test passed for $app. DownloadClient: $clientID, DownloadId: $downloadID and FilePath: $filePath" >> "$d" && exit 0

# Ensure we have necessary details
[ -z "$downloadID" ] && echo "DownloadID is empty from $app. Skipping cross-seed search. DownloadClient: $clientID and DownloadId: $downloadID" >> "$d" && exit 0
[ -z "$filePath" ] && echo "FilePath is empty from $app. Skipping cross-seed search. DownloadClient: $clientID and FilePath: $filePath" >> "$d" && exit 0

# Handle client based operations
case "$clientID" in
    "$torrentclientname")
        # echo "Client $torrentclientname triggered id search for DownloadId $downloadID with FilePath $filePath and FolderPath $folderPath"
        # xseed_resp=$(cross_seed_request "webhook" "infoHash=$downloadID")
        echo "client is: $clientID --> skipping (will run on torrent finished)" >> "$d"
        exit 0
        ;;
    "$usenetclientname")
        if [[ "$folderPath" =~ S[0-9]{1,2}(?!\.E[0-9]{1,2}) ]]; then
            echo "Client $usenetclientname skipped search for FolderPath $folderPath due to being a SeasonPack for Usenet" >> "$d"
            exit 0
        else
            echo "Client $usenetclientname triggered data search for DownloadId $downloadID using FilePath $filePath with FolderPath $folderPath" >> "$d"
            xseed_resp=$(cross_seed_request "webhook" "path=$filePath")
        fi
        ;;
    *)
        echo "|WARN| Client $clientID does not match configured Clients of $torrentclientname or $usenetclientname. Skipping..." >> "$d"
        exit 0
        ;;
esac

# Handle Cross Seed Response
if [ "$xseed_resp" == "204" ]; then
    echo "Success. Cross-seed search triggered by $app for DownloadClient: $clientID, DownloadId: $downloadID and FilePath: $filePath with FolderPath $folderPath" >> "$d"
    echo "$unique_id" >> "$log_file"
    exit 0
else
    echo "|WARN| Cross-seed webhook failed - HTTP Code $xseed_resp from $app for DownloadClient: $clientID, DownloadId: $downloadID and FilePath: $filePath with FolderPath $folderPath" >> "$d"
    exit 1
fi
