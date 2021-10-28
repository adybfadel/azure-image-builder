#!/bin/bash -e

# Add preview banner to MOTD
cat >> /etc/motd << EOF
*******************************************************
**        !! SIT ODJ Custom Linux VM Image !!        **
*******************************************************
EOF