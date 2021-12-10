#!/bin/bash

PLUGIN_DIR="$(cd "$(dirname "$0")"; pwd -P)"

exit_cleanup() {
  if [ "$?" -ne 0 ]; then
    echo "Plugin failed to install!"
    echo "Cleaning up..."
    . ."$PLUGIN_DIR"/uninstall.sh | grep -v "pluginuninstallend"
    if [ -d "$PLUGIN_DIR" ]; then
      echo "Removing plugin directory $PLUGIN_DIR"
      rm -rf "$PLUGIN_DIR"
    fi
  fi

  #required to end the plugin install
  echo "plugininstallend"
}
trap "exit_cleanup" EXIT

if grep -q Raspberry /proc/cpuinfo; then # on Raspberry Pi hardware
  echo "Installing fake packages for kernel, bootloader and pi lib"
  wget https://repo.volumio.org/Volumio2/Binaries/arm/libraspberrypi0_0.0.1_all.deb || { echo "Download of libraspberrypi0_0.0.1_all.deb failed"; exit 1; }
  wget https://repo.volumio.org/Volumio2/Binaries/arm/raspberrypi-bootloader_0.0.1_all.deb || { echo "Download of raspberrypi-bootloader_0.0.1_all.deb failed"; exit 1; }
  wget https://repo.volumio.org/Volumio2/Binaries/arm/raspberrypi-kernel_0.0.1_all.deb || { echo "Download of raspberrypi-kernel_0.0.1_all.deb failed"; exit 1; }
  dpkg -i libraspberrypi0_0.0.1_all.deb || { echo "Installation of libraspberrypi0_0.0.1_all.deb failed"; exit 1; }
  dpkg -i raspberrypi-bootloader_0.0.1_all.deb || { echo "Installation of raspberrypi-bootloader_0.0.1_all.deb failed"; exit 1; }
  dpkg -i raspberrypi-kernel_0.0.1_all.deb || { echo "Installation of raspberrypi-kernel_0.0.1_all.deb failed"; exit 1; }
  rm libraspberrypi0_0.0.1_all.deb
  rm raspberrypi-bootloader_0.0.1_all.deb
  rm raspberrypi-kernel_0.0.1_all.deb

  echo "Putting on hold packages for kernel, bootloader and pi lib"
  apt-mark hold libraspberrypi0 raspberrypi-bootloader raspberrypi-kernel || { echo "Putting on hold packages for kernel, bootloader and pi lib failed"; exit 1; }

  echo "Installing Chromium dependencies"
  apt-get update
  apt-get -y install || { echo "Installation of Chromium dependencies failed"; exit 1; }

  echo "Installing graphical environment"
  apt-get -y install xinit || { echo "Installation of xinit failed"; exit 1; }
  apt-get -y install xorg || { echo "Installation of xorg failed"; exit 1; }
  apt-get -y install openbox || { echo "Installation of openbox failed"; exit 1; }

  echo "Installing Chromium"
  apt-get -y install chromium-browser || { echo "Installation of Chromium failed"; exit 1; }

  echo "Creating /etc/X11/xorg.conf.d dir"
  mkdir /etc/X11/xorg.conf.d

  echo "Creating Xorg configuration file"
  echo "# This file is managed by the Touch Display plugin: Do not alter!
# It will be deleted when the Touch Display plugin gets uninstalled.
Section \"InputClass\"
        Identifier \"Touch rotation\"
        MatchIsTouchscreen \"on\"
        MatchDevicePath \"/dev/input/event*\"
        MatchDriver \"libinput|evdev\"
EndSection" > /etc/X11/xorg.conf.d/95-touch_display-plugin.conf || { echo "Creating Xorg configuration file failed"; exit 1; }
else # on other hardware
  echo "Installing Chromium dependencies"
  apt-get update
  apt-get -y install || { echo "Installation of Chromium dependencies failed"; exit 1; }

  echo "Installing graphical environment"
  apt-get -y install xinit || { echo "Installation of xinit failed"; exit 1; }
  apt-get -y install xorg || { echo "Installation of xorg failed"; exit 1; }
  apt-get -y install openbox || { echo "Installation of openbox failed"; exit 1; }

  echo "Installing Chromium"
  apt-get -y install chromium || { echo "Installation of Chromium failed"; exit 1; }
  ln -s /usr/bin/chromium /usr/bin/chromium-browser
fi

echo "Installing japanese, korean, chinese and taiwanese fonts"
apt-get -y install fonts-arphic-ukai fonts-arphic-gbsn00lp fonts-unfonts-core || { echo "Installation of fonts failed"; exit 1; }

echo "Creating Kiosk data dir"
mkdir /data/volumiokiosk
chown volumio:volumio /data/volumiokiosk

echo "Creating chromium kiosk start script"
echo "#!/bin/bash
while true; do timeout 3 bash -c \"</dev/tcp/127.0.0.1/3000\" >/dev/null 2>&1 && break; done
sed -i 's/\"exited_cleanly\":false/\"exited_cleanly\":true/' /data/volumiokiosk/Default/Preferences
sed -i 's/\"exit_type\":\"Crashed\"/\"exit_type\":\"None\"/' /data/volumiokiosk/Default/Preferences
if [ -L /data/volumiokiosk/SingletonCookie ]; then
  rm -rf /data/volumiokiosk/Singleton*
fi
openbox-session &
while true; do
  /usr/bin/chromium-browser \\
    --simulate-outdated-no-au='Tue, 31 Dec 2099 23:59:59 GMT' \\
    --force-device-scale-factor=1 \\
    --disable-pinch \\
    --kiosk \\
    --no-first-run \\
    --noerrdialogs \\
    --disable-3d-apis \\
    --disable-breakpad \\
    --disable-crash-reporter \\
    --disable-infobars \\
    --disable-session-crashed-bubble \\
    --disable-translate \\
    --user-data-dir='/data/volumiokiosk' \
    http://localhost:3000
done" > /opt/volumiokiosk.sh || { echo "Creating chromium kiosk start script failed"; exit 1; }
/bin/chmod +x /opt/volumiokiosk.sh

echo "Creating Systemd Unit for Kiosk"
echo "[Unit]
Description=Volumio Kiosk
Wants=volumio.service
After=volumio.service
[Service]
Type=simple
User=volumio
Group=volumio
ExecStart=/usr/bin/startx /etc/X11/Xsession /opt/volumiokiosk.sh -- -nocursor
[Install]
WantedBy=multi-user.target
" > /lib/systemd/system/volumio-kiosk.service || { echo "Creating Systemd Unit for Kiosk failed"; exit 1; }
systemctl daemon-reload

echo "Allowing volumio to start an xsession"
/bin/sed -i "s/allowed_users=console/allowed_users=anybody/" /etc/X11/Xwrapper.config || { echo "Allowing volumio to start an xsession failed"; exit 1; }
