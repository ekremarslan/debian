#!/bin/bash
set -e

echo -e "\n🌐 Sadece tr_TR.UTF-8 locale oluşturuluyor..."
apt update -y
apt install -y locales

sed -i 's/^# *tr_TR.UTF-8 UTF-8/tr_TR.UTF-8 UTF-8/' /etc/locale.gen
locale-gen

echo -e "\n✅ tr_TR.UTF-8 locale oluşturuldu ama sistem dili değiştirilmedi."
