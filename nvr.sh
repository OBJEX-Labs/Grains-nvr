#!/bin/bash

################################################################################
# NVR Script - Multi-camera recording management
# Saves clips in 1-minute segments and merges them every hour
################################################################################

# ==================== CONFIGURATION ====================

# Base directory for saving recordings
OUTPUT_DIR="/mnt/sec"

# Directory for merged hourly files
HOURLY_DIR="/mnt/sec/hourly"

# Duration of each clip in seconds (60 = 1 minute)
SEGMENT_DURATION=60

# Retention: delete files older than N hours (72 = 3 days)
RETENTION_HOURS=72

# Camera configuration (add or modify here)
declare -A CAMERAS
CAMERAS[camera1]="rtsp://user:password@x.x.x.x:554/stream0"
#CAMERAS[camera2]="rtsp://user:password@x.x.x.x:554/stream0"


# ==================== END CONFIGURATION ====================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Directory to store process PIDs
PID_DIR="/tmp/nvr_pids"
mkdir -p "$PID_DIR"

# Log file
LOG_FILE="$OUTPUT_DIR/nvr.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to create directories
setup_directories() {
    log "Creating directories..."
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$HOURLY_DIR"
    
    for camera_name in "${!CAMERAS[@]}"; do
        mkdir -p "$OUTPUT_DIR/$camera_name"
        mkdir -p "$HOURLY_DIR/$camera_name"
        log "  - $OUTPUT_DIR/$camera_name"
    done
    
    echo -e "${GREEN}✓ Directories created${NC}"
}

# Function to start recording for a single camera
start_camera_recording() {
    local camera_name=$1
    local rtsp_url=$2
    local output_path="$OUTPUT_DIR/$camera_name"
    
    log "Starting recording: $camera_name"
    
    # Start FFmpeg with timeout (compatible with FFmpeg 6.1.1)
    nohup ffmpeg -hide_banner \
           -loglevel error \
           -rtsp_transport tcp \
           -i "$rtsp_url" \
           -c:v copy \
           -c:a aac \
           -f segment \
           -segment_time "$SEGMENT_DURATION" \
           -segment_format mkv \
           -reset_timestamps 1 \
           -strftime 1 \
           "$output_path/${camera_name}_%Y%m%d_%H%M%S.mkv" \
           >> "$LOG_FILE" 2>&1 &
    
    # Save the PID
    local pid=$!
    echo $pid > "$PID_DIR/$camera_name.pid"
    echo $(date +%s) > "$PID_DIR/$camera_name.lastcheck"
    
    # Wait 3 seconds and verify it started
    sleep 3
    if ps -p $pid > /dev/null 2>&1; then
        echo -e "${GREEN}✓ $camera_name started (PID: $pid)${NC}"
    else
        echo -e "${RED}✗ $camera_name FAILED (unable to connect)${NC}"
        log "ERROR: $camera_name unable to connect to $rtsp_url"
    fi
}

# Function to merge videos from the last hour
merge_hourly_videos() {
    local camera_name=$1
    local camera_dir="$OUTPUT_DIR/$camera_name"
    local hourly_output_dir="$HOURLY_DIR/$camera_name"
    
    # Calculate timestamp from one hour ago
    local one_hour_ago=$(date -d '1 hour ago' '+%Y%m%d_%H')
    
    # Find all files from the previous hour
    local video_files=$(find "$camera_dir" -name "${camera_name}_${one_hour_ago}*.mkv" -type f | sort)
    
    if [ -z "$video_files" ]; then
        log "  - $camera_name: no files to merge for hour $one_hour_ago"
        return
    fi
    
    local file_count=$(echo "$video_files" | wc -l)
    log "  - $camera_name: found $file_count files for hour $one_hour_ago"
    
    # Output file name
    local output_file="$hourly_output_dir/${camera_name}_${one_hour_ago}00.mkv"
    
    # Create temporary file list for FFmpeg
    local filelist="/tmp/merge_${camera_name}_${one_hour_ago}.txt"
    > "$filelist"
    
    for video in $video_files; do
        echo "file '$video'" >> "$filelist"
    done
    
    # Merge with FFmpeg (concat demuxer - fast, no re-encoding)
    log "  - $camera_name: merging in progress -> $(basename $output_file)"
    
    if ffmpeg -f concat -safe 0 -i "$filelist" -c copy "$output_file" >> "$LOG_FILE" 2>&1; then
        log "  - $camera_name: merge completed successfully"
        
        # Delete original 1-minute files
        for video in $video_files; do
            rm "$video"
        done
        log "  - $camera_name: removed $file_count original files"
    else
        log "  - $camera_name: ERROR during merge"
    fi
    
    # Remove temporary file list
    rm -f "$filelist"
}

# Watchdog function to monitor and restart crashed cameras
watchdog_monitor() {
    log "Starting watchdog monitor..."
    
    while true; do
        sleep 300  # Check every 5 minutes
        
        log "========== WATCHDOG CHECK =========="
        
        for camera_name in "${!CAMERAS[@]}"; do
            local pid_file="$PID_DIR/$camera_name.pid"
            local lastcheck_file="$PID_DIR/$camera_name.lastcheck"
            
            # Verify that the process exists
            if [ -f "$pid_file" ]; then
                local pid=$(cat "$pid_file")
                
                if ! ps -p $pid > /dev/null 2>&1; then
                    log "⚠ WATCHDOG: $camera_name process dead (PID: $pid), restarting..."
                    rm -f "$pid_file"
                    start_camera_recording "$camera_name" "${CAMERAS[$camera_name]}"
                    continue
                fi
                
                # Verify that it's actually writing files
                local camera_dir="$OUTPUT_DIR/$camera_name"
                local latest_file=$(find "$camera_dir" -name "*.mkv" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
                
                if [ -n "$latest_file" ]; then
                    local file_age=$(( $(date +%s) - $(stat -c %Y "$latest_file" 2>/dev/null || echo 0) ))
                    
                    # If the last file is older than 5 minutes, there's a problem
                    if [ $file_age -gt 300 ]; then
                        log "⚠ WATCHDOG: $camera_name hasn't written for $file_age seconds, restarting..."
                        kill $pid 2>/dev/null
                        rm -f "$pid_file"
                        sleep 2
                        start_camera_recording "$camera_name" "${CAMERAS[$camera_name]}"
                    else
                        log "✓ $camera_name: OK (last file: $((file_age))s ago)"
                    fi
                else
                    log "⚠ WATCHDOG: $camera_name no files found, possible connection problem"
                fi
            else
                log "⚠ WATCHDOG: $camera_name not running, starting..."
                start_camera_recording "$camera_name" "${CAMERAS[$camera_name]}"
            fi
        done
        
        log "========== WATCHDOG COMPLETED =========="
    done
}

# Function to start automatic hourly merge
start_hourly_merge() {
    log "Starting hourly merge task..."
    
    # Script that runs every hour
    while true; do
        # Wait until minute 5 of the next hour (to allow files to complete)
        local current_minute=$(date '+%M')
        local sleep_seconds=$(( (65 - 10#$current_minute) * 60 ))
        
        if [ $sleep_seconds -lt 300 ]; then
            sleep_seconds=$((sleep_seconds + 3600))
        fi
        
        log "Next hourly merge in $(($sleep_seconds / 60)) minutes..."
        sleep $sleep_seconds
        
        log "========== HOURLY MERGE =========="
        for camera_name in "${!CAMERAS[@]}"; do
            merge_hourly_videos "$camera_name"
        done
        log "========== MERGE COMPLETED =========="
    done
}

# Function to start all cameras
start_all() {
    log "========== STARTING NVR =========="
    setup_directories
    
    # Start recordings
    for camera_name in "${!CAMERAS[@]}"; do
        start_camera_recording "$camera_name" "${CAMERAS[$camera_name]}"
        sleep 2  # Small delay between starts
    done
    
    # Start hourly merge task in background
    nohup bash -c "$(declare -f log); $(declare -f merge_hourly_videos); $(declare -p CAMERAS); $(declare -p OUTPUT_DIR); $(declare -p HOURLY_DIR); $(declare -p LOG_FILE); $(declare -f start_hourly_merge); start_hourly_merge" >> "$LOG_FILE" 2>&1 &
    
    local merge_pid=$!
    echo $merge_pid > "$PID_DIR/hourly_merge.pid"
    
    # Start watchdog monitor
    nohup bash -c "$(declare -f log); $(declare -f start_camera_recording); $(declare -f watchdog_monitor); $(declare -p CAMERAS); $(declare -p OUTPUT_DIR); $(declare -p PID_DIR); $(declare -p LOG_FILE); $(declare -p SEGMENT_DURATION); watchdog_monitor" >> "$LOG_FILE" 2>&1 &
    
    local watchdog_pid=$!
    echo $watchdog_pid > "$PID_DIR/watchdog.pid"
    
    echo -e "\n${GREEN}✓ All cameras started${NC}"
    echo -e "${GREEN}✓ Hourly merge task started (PID: $merge_pid)${NC}"
    echo -e "${GREEN}✓ Watchdog monitor started (PID: $watchdog_pid)${NC}"
    echo -e "Log: $LOG_FILE"
    echo -e "Recordings: $OUTPUT_DIR"
    echo -e "Hourly files: $HOURLY_DIR"
}

# Function to stop a camera
stop_camera() {
    local camera_name=$1
    local pid_file="$PID_DIR/$camera_name.pid"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p $pid > /dev/null 2>&1; then
            log "Stopping recording: $camera_name (PID: $pid)"
            kill $pid
            rm "$pid_file"
            echo -e "${GREEN}✓ $camera_name stopped${NC}"
        else
            echo -e "${YELLOW}! $camera_name is not running${NC}"
            rm "$pid_file"
        fi
    else
        echo -e "${YELLOW}! PID file not found for $camera_name${NC}"
    fi
}

# Function to stop all cameras
stop_all() {
    log "========== STOPPING NVR =========="
    
    # Stop cameras
    for camera_name in "${!CAMERAS[@]}"; do
        stop_camera "$camera_name"
    done
    
    # Stop watchdog
    if [ -f "$PID_DIR/watchdog.pid" ]; then
        local watchdog_pid=$(cat "$PID_DIR/watchdog.pid")
        if ps -p $watchdog_pid > /dev/null 2>&1; then
            log "Stopping watchdog monitor (PID: $watchdog_pid)"
            kill $watchdog_pid
            rm "$PID_DIR/watchdog.pid"
            echo -e "${GREEN}✓ Watchdog stopped${NC}"
        fi
    fi
    
    # Stop hourly merge task
    if [ -f "$PID_DIR/hourly_merge.pid" ]; then
        local merge_pid=$(cat "$PID_DIR/hourly_merge.pid")
        if ps -p $merge_pid > /dev/null 2>&1; then
            log "Stopping hourly merge task (PID: $merge_pid)"
            kill $merge_pid
            rm "$PID_DIR/hourly_merge.pid"
            echo -e "${GREEN}✓ Hourly merge task stopped${NC}"
        fi
    fi
    
    echo -e "${GREEN}✓ All cameras stopped${NC}"
}

# Function to display status
status() {
    echo -e "\n${YELLOW}========== NVR STATUS ==========${NC}\n"
    
    for camera_name in "${!CAMERAS[@]}"; do
        local pid_file="$PID_DIR/$camera_name.pid"
        
        if [ -f "$pid_file" ]; then
            local pid=$(cat "$pid_file")
            if ps -p $pid > /dev/null 2>&1; then
                echo -e "${GREEN}✓${NC} $camera_name: RUNNING (PID: $pid)"
                
                # Count recorded files
                local file_count=$(ls -1 "$OUTPUT_DIR/$camera_name"/*.mkv 2>/dev/null | wc -l)
                local disk_usage=$(du -sh "$OUTPUT_DIR/$camera_name" 2>/dev/null | cut -f1)
                local hourly_count=$(ls -1 "$HOURLY_DIR/$camera_name"/*.mkv 2>/dev/null | wc -l)
                local hourly_usage=$(du -sh "$HOURLY_DIR/$camera_name" 2>/dev/null | cut -f1)
                
                echo -e "   1min clips: $file_count ($disk_usage) | Hourly files: $hourly_count ($hourly_usage)"
            else
                echo -e "${RED}✗${NC} $camera_name: STOPPED (stale PID)"
            fi
        else
            echo -e "${RED}✗${NC} $camera_name: STOPPED"
        fi
        echo ""
    done
    
    # Merge task status
    if [ -f "$PID_DIR/hourly_merge.pid" ]; then
        local merge_pid=$(cat "$PID_DIR/hourly_merge.pid")
        if ps -p $merge_pid > /dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Hourly merge task: RUNNING (PID: $merge_pid)"
        else
            echo -e "${RED}✗${NC} Hourly merge task: STOPPED"
        fi
    else
        echo -e "${RED}✗${NC} Hourly merge task: STOPPED"
    fi
    
    # Watchdog status
    echo ""
    if [ -f "$PID_DIR/watchdog.pid" ]; then
        local watchdog_pid=$(cat "$PID_DIR/watchdog.pid")
        if ps -p $watchdog_pid > /dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Watchdog monitor: RUNNING (PID: $watchdog_pid)"
        else
            echo -e "${RED}✗${NC} Watchdog monitor: STOPPED"
        fi
    else
        echo -e "${RED}✗${NC} Watchdog monitor: STOPPED"
    fi
}

# Function to clean up old files
cleanup() {
    log "========== CLEANING OLD FILES =========="
    
    for camera_name in "${!CAMERAS[@]}"; do
        # Clean up 1-minute clips
        local camera_dir="$OUTPUT_DIR/$camera_name"
        if [ -d "$camera_dir" ]; then
            log "Cleaning $camera_name 1min clips (removing files older than $RETENTION_HOURS hours)"
            local deleted=$(find "$camera_dir" -name "*.mkv" -type f -mmin +$((RETENTION_HOURS * 60)) -delete -print | wc -l)
            log "  - 1min clips deleted: $deleted"
        fi
        
        # Clean up hourly files
        local hourly_camera_dir="$HOURLY_DIR/$camera_name"
        if [ -d "$hourly_camera_dir" ]; then
            log "Cleaning $camera_name hourly files (removing files older than $RETENTION_HOURS hours)"
            local deleted_hourly=$(find "$hourly_camera_dir" -name "*.mkv" -type f -mmin +$((RETENTION_HOURS * 60)) -delete -print | wc -l)
            log "  - Hourly files deleted: $deleted_hourly"
        fi
    done
    
    echo -e "${GREEN}✓ Cleanup completed${NC}"
}

# Function to restart everything
restart() {
    log "========== RESTARTING NVR =========="
    stop_all
    sleep 3
    start_all
}

# Function to show help
show_help() {
    echo ""
    echo "NVR Management Script"
    echo "====================="
    echo ""
    echo "Usage: $0 {start|stop|restart|status|cleanup|merge|help}"
    echo ""
    echo "Commands:"
    echo "  start    - Start recording for all cameras + hourly merge"
    echo "  stop     - Stop all recordings"
    echo "  restart  - Restart all recordings"
    echo "  status   - Show recording status"
    echo "  cleanup  - Delete files older than $RETENTION_HOURS hours"
    echo "  merge    - Force manual merge of last hour for all cameras"
    echo "  help     - Show this message"
    echo ""
    echo "Current configuration:"
    echo "  - Clip output: $OUTPUT_DIR"
    echo "  - Hourly output: $HOURLY_DIR"
    echo "  - Clip duration: $SEGMENT_DURATION seconds"
    echo "  - Retention: $RETENTION_HOURS hours"
    echo "  - Configured cameras: ${#CAMERAS[@]}"
    echo ""
}

# Function to force manual merge
force_merge() {
    log "========== MANUAL MERGE =========="
    for camera_name in "${!CAMERAS[@]}"; do
        merge_hourly_videos "$camera_name"
    done
    echo -e "${GREEN}✓ Merge completed${NC}"
}

# ==================== MAIN ====================

case "$1" in
    start)
        start_all
        ;;
    stop)
        stop_all
        ;;
    restart)
        restart
        ;;
    status)
        status
        ;;
    cleanup)
        cleanup
        ;;
    merge)
        force_merge
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Error: Unrecognized command${NC}"
        show_help
        exit 1
        ;;
esac

exit 0