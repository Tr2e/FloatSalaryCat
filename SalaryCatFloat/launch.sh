#!/bin/bash
# Quick launch 月薪喵 desktop companion
APP="$(cd "$(dirname "$0")" && pwd)/dist/月薪喵.app"

# Kill existing instance if running
pkill -f "月薪喵" 2>/dev/null || true
sleep 0.5

open "$APP"
echo "🐱 月薪喵 launched! Look at your desktop."
