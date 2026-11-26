"""Render signing options for the iPhone app and its widget extension."""
import os
from pathlib import Path
import plistlib
import sys

data = plistlib.loads(Path(__file__).with_name("ExportOptions.plist").read_bytes())
data["teamID"] = os.environ["TEAM_ID"]
app_id = os.environ.get("APP_ID", "com.hgsldswk.before3pm")
data["provisioningProfiles"] = {
    app_id: os.environ.get("APP_PROFILE", "Before3PM AppStore"),
    f"{app_id}.widget": os.environ.get("WIDGET_PROFILE", "Before3PM Widget AppStore"),
}
sys.stdout.buffer.write(plistlib.dumps(data))
