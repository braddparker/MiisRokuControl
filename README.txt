Roku Control for MIOS basic usage:

Upload files to Vera under Apps->Develop Apps->Luup files.

Make sure your Roku device is powered on. It must have a known, static IP address.

Create a new device: Apps->Develop Apps->Create Device.

Upnp Device Filename: D_RokuControl1.xml
Upnp Implementation Filename: I_RokuControl1.xml
IP address: <Your Roku's IP address>

Description and Room are optional. All other fields should be left blank.

Click "Create Device"

Restart luup, then refresh your browser.

You should see your new Roku device. You may now give it a custom name if you don't like the one provided.



