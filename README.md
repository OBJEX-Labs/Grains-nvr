# NVR Multi-Camera Recording System

A production-ready Network Video Recorder (NVR) system for continuous recording from multiple IP cameras with automatic file management and failover capabilities.

Part of the Grains software suite by OBJEX LAB SRL. Grains are minimal, single-purpose, production-ready building blocks designed for reliability and simplicity.

## Overview

This NVR system provides continuous video recording from RTSP-enabled IP cameras with the following workflow:

1. Records video streams in 1-minute segments
2. Automatically merges segments into hourly files
3. Monitors camera health and automatically restarts failed streams
4. Manages disk space through configurable retention policies
5. Runs as a systemd service with automatic startup on boot

## Features

- Continuous recording with configurable segment duration
- Automatic hourly consolidation of video segments
- Watchdog process monitors camera health every 5 minutes
- Automatic restart of failed camera streams
- Configurable retention policy for automatic cleanup
- Stream copy mode (no transcoding) for minimal CPU usage
- Systemd integration for automatic startup and process management
- Detailed logging for monitoring and troubleshooting
- Support for multiple cameras with independent monitoring

## System Requirements

- Linux operating system (tested on Ubuntu Server 24.04.3 LTS)
- FFmpeg 6.1.1 or later
- Bash 4.0 or later
- Systemd init system
- Sufficient storage for video retention period
- Network connectivity to IP cameras via RTSP

## Quick Start

### Installation

1. Clone this repository or download the files:
```bash
git clone <repository-url>
cd nvr-grain
```

2. Edit `nvr.service` to match your system:
```bash
nano nvr.service
# Replace 'your_user' and 'your_group' with your actual system user
# Update paths to match your home directory
```

3. Edit `nvr.sh` configuration section:
```bash
nano nvr.sh
# Configure OUTPUT_DIR, camera URLs, retention policy, etc.
```

4. Run the installation script:
```bash
chmod +x install_nvr.sh
./install_nvr.sh
```

The installer will copy files, configure the systemd service, and optionally start the NVR system.

## Configuration

### Main Configuration File: nvr.sh

Edit the configuration section at the top of `nvr.sh`:

```bash
# Base directory for saving recordings
OUTPUT_DIR="/path/to/storage"

# Directory for merged hourly files
HOURLY_DIR="/path/to/storage/hourly"

# Duration of each clip in seconds (60 = 1 minute)
SEGMENT_DURATION=60

# Retention: delete files older than N hours (72 = 3 days)
RETENTION_HOURS=72

# Camera configuration (add or modify here)
declare -A CAMERAS
CAMERAS[camera1]="rtsp://user:password@192.168.1.10:554/stream0"
CAMERAS[camera2]="rtsp://user:password@192.168.1.11:554/stream0"
```

### Camera Configuration

Add cameras by adding entries to the CAMERAS array:
```bash
CAMERAS[camera_name]="rtsp://username:password@camera_ip:port/stream_path"
```

Disable a camera by commenting out its line:
```bash
#CAMERAS[camera3]="rtsp://user:password@192.168.1.12:554/stream0"
```

### Systemd Service Configuration

Edit `nvr.service` before installation to customize:
- User and group for running the service
- Working directory path
- Script execution paths
- Resource limits (optional)

## Usage

### Service Management (Systemd)

```bash
# Start the service
sudo systemctl start nvr

# Stop the service
sudo systemctl stop nvr

# Restart the service
sudo systemctl restart nvr

# Check service status
sudo systemctl status nvr

# View live logs
sudo journalctl -u nvr -f

# Disable automatic startup
sudo systemctl disable nvr

# Enable automatic startup
sudo systemctl enable nvr
```

### Direct Script Commands

```bash
# Check recording status
~/nvr.sh status

# Start recording manually (if not using systemd)
~/nvr.sh start

# Stop all recordings
~/nvr.sh stop

# Restart recordings
~/nvr.sh restart

# Clean up old files
~/nvr.sh cleanup

# Force manual hourly merge
~/nvr.sh merge

# Show help
~/nvr.sh help
```

## File Structure

The system creates the following directory structure:

```
/path/to/storage/
├── camera1/
│   ├── camera1_20260205_093000.mkv  (1-minute clip)
│   ├── camera1_20260205_093100.mkv
│   └── ...
├── camera2/
│   └── ...
├── hourly/
│   ├── camera1/
│   │   ├── camera1_20260205_0900.mkv  (1-hour file)
│   │   ├── camera1_20260205_1000.mkv
│   │   └── ...
│   └── camera2/
│       └── ...
└── nvr.log
```

### File Naming Convention

**1-minute clips:**
- Format: `{camera_name}_{YYYYMMDD}_{HHMMSS}.mkv`
- Example: `camera1_20260205_093045.mkv`
- Represents: Camera1, February 5 2026, 09:30:45

**Hourly files:**
- Format: `{camera_name}_{YYYYMMDD}_{HHMM}.mkv`
- Example: `camera1_20260205_0900.mkv`
- Represents: Camera1, February 5 2026, 09:00-10:00

## Monitoring

### Check System Status

```bash
# Display detailed status
~/nvr.sh status

# Sample output:
# ========== NVR STATUS ==========
#
# ✓ camera1: RUNNING (PID: 5196)
#    1min clips: 45 (85M) | Hourly files: 2 (1.2G)
#
# ✓ camera2: RUNNING (PID: 5219)
#    1min clips: 45 (92M) | Hourly files: 2 (1.3G)
#
# ✓ Hourly merge task: RUNNING (PID: 5259)
# ✓ Watchdog monitor: RUNNING (PID: 5260)
```

### View Logs

```bash
# Application log
tail -f /path/to/storage/nvr.log

# Systemd logs (last 100 lines)
sudo journalctl -u nvr -n 100

# Follow systemd logs in real-time
sudo journalctl -u nvr -f

# Search for errors
grep -i error /path/to/storage/nvr.log
```

### Monitor Disk Usage

```bash
# Total space used
du -sh /path/to/storage

# Space per camera
du -sh /path/to/storage/camera*
du -sh /path/to/storage/hourly/*

# Available disk space
df -h /path/to/storage

# Count of video files
find /path/to/storage -name "*.mkv" | wc -l
```

## Maintenance

### Automatic Cleanup

Files older than `RETENTION_HOURS` are automatically removed:

```bash
# Manual cleanup
~/nvr.sh cleanup
```

### Scheduled Cleanup with Cron

To automate cleanup every 6 hours:

```bash
crontab -e

# Add this line:
0 */6 * * * /home/your_user/nvr.sh cleanup >> /home/your_user/nvr_cleanup.log 2>&1
```

### Hourly Merge Process

The system automatically merges 1-minute clips into hourly files:

1. Every hour at minute :05, the merge task activates
2. Collects all 1-minute clips from the previous hour
3. Concatenates them using FFmpeg's concat demuxer (no re-encoding)
4. Saves the result as a single hourly file
5. Deletes the original 1-minute clips
6. Process typically completes in 10-30 seconds with minimal CPU usage

Recording continues uninterrupted during the merge process.

### Watchdog Monitoring

The watchdog process runs every 5 minutes and:

- Verifies all FFmpeg processes are running
- Checks that cameras are actively writing files
- Automatically restarts crashed or stalled streams
- Logs all restart attempts and failures

## Troubleshooting

### Service Won't Start

```bash
# Check service status
sudo systemctl status nvr

# View detailed logs
sudo journalctl -u nvr -n 100

# Verify script permissions
ls -la ~/nvr.sh

# Verify directory permissions
ls -ld /path/to/storage
```

**Common fixes:**
```bash
# Grant execute permission
chmod +x ~/nvr.sh

# Fix directory ownership
sudo chown -R your_user:your_group /path/to/storage
```

### Camera Not Recording

```bash
# Check status
~/nvr.sh status

# Test RTSP connection manually
ffmpeg -rtsp_transport tcp -i rtsp://user:pass@camera_ip:554/stream0 -t 10 test.mkv

# Verify network connectivity
ping camera_ip

# Check for errors in logs
grep camera_name /path/to/storage/nvr.log | tail -20
```

**Common issues:**
- Incorrect IP address or port
- Wrong username/password
- Camera powered off
- Network firewall blocking RTSP port (default 554)

### Hourly Merge Not Working

```bash
# Force manual merge
~/nvr.sh merge

# Verify merge task is running
ps aux | grep merge

# Check merge logs
grep -i merge /path/to/storage/nvr.log

# Verify 1-minute clips exist
ls -lh /path/to/storage/camera1/
```

### Disk Full

```bash
# Check available space
df -h /path/to/storage

# Immediate cleanup
~/nvr.sh cleanup

# Reduce retention period
nano ~/nvr.sh
# Change RETENTION_HOURS from 72 to 48
sudo systemctl restart nvr
```

### High CPU Usage

```bash
# Check CPU usage
top

# Find FFmpeg processes
ps aux | grep ffmpeg
```

With stream copy mode (`-c:v copy`), FFmpeg should use only 2-5% CPU per camera. Higher usage may indicate:
- Accidental transcoding (verify `-c:v copy` is present)
- Network issues causing retransmissions
- Camera sending unreadable streams

### Watchdog Not Restarting Cameras

```bash
# Verify watchdog is running
ps aux | grep watchdog

# Check watchdog logs
grep WATCHDOG /path/to/storage/nvr.log

# Restart entire system
sudo systemctl restart nvr
```

## Performance Characteristics

### CPU Usage
- Stream copy mode: 2-5% per camera
- 4 cameras: approximately 10-20% total CPU
- Hourly merge: 5-10% CPU for 10-30 seconds

### Network Bandwidth
- 1080p camera: 2-4 Mbps per stream
- 4 cameras: approximately 10-15 Mbps total

### Storage Requirements
- 1080p @ 25fps: 2-4 GB per camera per day
- 4 cameras: 10-15 GB per day
- 72-hour retention: 30-45 GB total

### File Sizes
- 1-minute clip: 20-40 MB (varies with bitrate)
- 1-hour file: 1.2-2.4 GB

## Security Considerations

- Camera credentials are stored in plaintext in `nvr.sh`
- Protect the script file with appropriate permissions: `chmod 600 ~/nvr.sh`
- Use strong passwords for camera access
- Consider using a firewall to restrict RTSP port access
- For remote access, use VPN or SSH tunneling

## License

MIT License
Copyright (c) 2026 OBJEX LAB SRL

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Support

For issues, questions, or contributions, please refer to the repository's issue tracker or contact OBJEX LAB SRL directly (info@objexlabs.com).