# Read-only audit of the animals table. Flags rows that look wrong and writes audit_report.csv.
# Needs SUPABASE_URL and SUPABASE_SERVICE_KEY (or SUPABASE_KEY) in .env or the environment.
# Any key that can SELECT from `animals` works, including the anon key.

import csv
import os
import re
from collections import Counter, defaultdict

import requests

from env import load_env

load_env()

SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY") or os.environ["SUPABASE_SERVICE_KEY"]
HEADERS = {"apikey": SUPABASE_KEY, "Authorization": f"Bearer {SUPABASE_KEY}"}

# words a real animal description almost always contains somewhere
ANIMAL_WORDS = {
    "species",
    "genus",
    "family",
    "animal",
    "mammal",
    "bird",
    "fish",
    "reptile",
    "amphibian",
    "insect",
    "arachnid",
    "crustacean",
    "mollusc",
    "mollusk",
    "subspecies",
    "breed",
    "carnivore",
    "herbivore",
    "omnivore",
    "predator",
    "native",
    "endemic",
    "found in",
    "lives in",
    "inhabit",
    "marsupial",
    "rodent",
    "primate",
    "snake",
    "lizard",
    "shark",
    "whale",
    "dolphin",
    "spider",
}
BAD_OPENINGS = (
    "this is a list",
    "list of",
    "may refer to",
    "disambiguation",
    "can refer to",
)
# scientific names shared by every dog / cat breed, so photos and facts are unreliable
DOMESTIC_SCIENTIFIC = {
    "canis lupus",
    "canis lupus familiaris",
    "felis catus",
    "felis silvestris catus",
}


def fetch_all():
    rows, start, size = [], 0, 1000
    while True:
        r = requests.get(
            f"{SUPABASE_URL}/rest/v1/animals",
            params={
                "select": "id,name,habitat,diet,image_url,description,json_data",
                "order": "id.asc",
                "offset": start,
                "limit": size,
            },
            headers=HEADERS,
            timeout=30,
        )
        r.raise_for_status()
        batch = r.json()
        rows += batch
        if len(batch) < size:
            return rows
        start += size


def has_digit(text):
    return bool(text) and bool(re.search(r"\d", text))


def audit(rows):
    image_use = defaultdict(list)
    for row in rows:
        if row.get("image_url"):
            image_use[row["image_url"]].append(row["name"])

    flagged = []
    for row in rows:
        flags = []
        name = row["name"] or ""
        desc = (row.get("description") or "").strip()
        data = row.get("json_data") or {}
        tax = data.get("taxonomy") or {}
        chars = data.get("characteristics") or {}
        sci = (tax.get("scientific_name") or "").strip()
        genus = (tax.get("genus") or "").strip().lower()
        lifespan = chars.get("lifespan")

        # description
        if not desc:
            flags.append("desc_missing")
        else:
            low = desc.lower()
            if len(desc) < 80:
                flags.append("desc_short")
            if low.startswith(BAD_OPENINGS):
                flags.append("desc_list_or_disambiguation")
            if not any(w in low for w in ANIMAL_WORDS):
                flags.append("desc_not_animal_like")
            name_tokens = [t for t in re.findall(r"[a-z]+", name.lower()) if len(t) > 3]
            anchors = (
                name_tokens
                + ([genus] if genus else [])
                + ([sci.lower()] if sci else [])
            )
            if anchors and not any(a in low for a in anchors):
                flags.append("desc_never_mentions_animal")

        # taxonomy / classification
        if not sci:
            flags.append("no_scientific_name")
        elif sci.lower() in DOMESTIC_SCIENTIFIC and name.lower() not in {
            "dog",
            "cat",
            "wolf",
            "domestic dog",
            "domestic cat",
        }:
            flags.append("domestic_breed")

        # lifespan
        if not lifespan:
            flags.append("lifespan_missing")
        elif not has_digit(lifespan):
            flags.append("lifespan_unparseable")

        # other attributes
        if not row.get("habitat"):
            flags.append("habitat_missing")
        if not row.get("diet"):
            flags.append("diet_missing")

        # image
        if not row.get("image_url"):
            flags.append("image_missing")
        elif len(image_use[row["image_url"]]) > 1:
            flags.append("image_shared")

        flagged.append((row, flags))
    return flagged


def main():
    rows = fetch_all()
    results = audit(rows)
    total = len(rows)

    counts = Counter(f for _, flags in results for f in flags)
    clean = sum(1 for _, flags in results if not flags)
    serious = {
        "desc_missing",
        "desc_list_or_disambiguation",
        "desc_not_animal_like",
        "desc_never_mentions_animal",
        "no_scientific_name",
        "domestic_breed",
        "image_missing",
        "image_shared",
    }
    needs_work = sum(1 for _, flags in results if serious & set(flags))

    print(f"\n{total} animals audited\n")
    for flag, n in counts.most_common():
        print(f"  {flag:32} {n:5}  ({n / total:5.1%})")
    print(f"\n  rows with no flags at all        {clean:5}")
    print(
        f"  rows with a serious flag         {needs_work:5}  <- these need re-fetching"
    )

    with open("audit_report.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(
            ["id", "name", "scientific_name", "flags", "description_start", "image_url"]
        )
        for row, flags in results:
            if flags:
                sci = ((row.get("json_data") or {}).get("taxonomy") or {}).get(
                    "scientific_name", ""
                )
                w.writerow(
                    [
                        row["id"],
                        row["name"],
                        sci,
                        ";".join(flags),
                        (row.get("description") or "")[:120].replace("\n", " "),
                        row.get("image_url") or "",
                    ]
                )
    print("\nwrote audit_report.csv")


if __name__ == "__main__":
    main()
