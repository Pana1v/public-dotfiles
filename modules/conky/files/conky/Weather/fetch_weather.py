#!/usr/bin/env python3
"""Weather for the conky Weather panel, from wttr.in (no API key).

No location in the URL: wttr.in geolocates the caller's IP, so the
resolved area is printed too, making a VPN/Tailscale misfire visible.

Output, tab-separated, one record per line:
  L  area, region
  N  temp_c, feels_c, description, humidity, wind_kmph, rain_chance_now
  S  sunrise, sunset
  H  hour, temp_c, rain_chance            (next 4 three-hour slots)
  D  weekday, min_c, max_c, rain_chance, description   (3 days)
Prints nothing on failure so the caller keeps its last-good cache.
"""

import json
import urllib.request
from datetime import datetime

URL = "https://wttr.in/?format=j1"
HOURLY_SLOTS = 4


def desc(entry: dict) -> str:
    return entry["weatherDesc"][0]["value"].strip()


def main() -> None:
    req = urllib.request.Request(URL, headers={"User-Agent": "curl/8"})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:  # noqa: S310
            data = json.loads(resp.read())
    except Exception:
        return

    area = data["nearest_area"][0]
    now = data["current_condition"][0]
    days = data["weather"]

    # Hourly slots are 3h apart ("0", "300", ... "2100"); take the
    # upcoming ones, spilling into tomorrow.
    hour_now = datetime.now().hour
    slots = []
    for day_idx, day in enumerate(days[:2]):
        for h in day["hourly"]:
            hour = int(h["time"]) // 100
            if day_idx == 0 and hour + 3 <= hour_now:
                continue
            slots.append((hour, h))
    rain_now = slots[0][1]["chanceofrain"] if slots else "0"

    print(f"L\t{area['areaName'][0]['value']}, {area['region'][0]['value']}")
    print(
        f"N\t{now['temp_C']}\t{now['FeelsLikeC']}\t{desc(now)}\t"
        f"{now['humidity']}\t{now['windspeedKmph']}\t{rain_now}"
    )
    astro = days[0]["astronomy"][0]
    print(f"S\t{astro['sunrise']}\t{astro['sunset']}")

    for hour, h in slots[1:HOURLY_SLOTS + 1]:
        print(f"H\t{hour:02d}:00\t{h['tempC']}\t{h['chanceofrain']}")

    for day in days:
        weekday = datetime.strptime(day["date"], "%Y-%m-%d").strftime("%a")
        rain = max(int(h["chanceofrain"]) for h in day["hourly"])
        midday = day["hourly"][len(day["hourly"]) // 2]
        print(f"D\t{weekday}\t{day['mintempC']}\t{day['maxtempC']}\t{rain}\t{desc(midday)}")


if __name__ == "__main__":
    main()
