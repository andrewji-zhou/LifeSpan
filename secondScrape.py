import os
import requests 
from supabase import create_client, Client
import time
import string
import wikipedia

# configuration with keys and urls, read from the environment (see .env.example)
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_KEY"]
SUPABASE_URL = os.environ["SUPABASE_URL"]

API_NINJA_KEY = os.environ["API_NINJA_KEY"]
PEXELS_API_KEY = os.environ["PEXELS_API_KEY"]

#initiate supabase admin client
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

def get_seed_list(): 
    print("starting animal scrape") 
    
    # create the list as a set so that all elements are unique and duplicates are removed
    unique_names = set()
    
    # creates a string named alphabet thats just all the lowercase letters
    alphabet = string.ascii_lowercase
    
    for letter in alphabet:
        print(f"searching for animals using {letter}")
        API_NINJA_URL = f"https://api.api-ninjas.com/v1/animals?name={letter}"
        try :
            # sends request and stores response in response
            response = requests.get(API_NINJA_URL, headers = {'X-Api-Key' : API_NINJA_KEY})
            # if response is valid
            if response.status_code == 200 :
                data = response.json()
                
                # iterates through the list of animals returned
                for animal in data:
                    name = animal.get('name')
                    # if name is valid then do this
                    if name :
                        unique_names.add(name) # adds to set 
                    else :
                        print(f"error processing letter '{letter}' : {response.status_code}")
        except Exception as e :
            print(f"network error on {letter} : {e}")
            
        # reduces frequence of api calls
        time.sleep(0.5)
        
    final_list = list(unique_names)
    print(f"scrape complete. found {len(final_list)} unique animals")
    return final_list


def get_animal_data(name):
    API_NINJA_URL = f"https://api.api-ninjas.com/v1/animals?name={name}"
    try: 
        # shoots a call to the api retreiving the json for that animal 
        response = requests.get(API_NINJA_URL, headers = {'X-Api-Key' : API_NINJA_KEY})
        # if the response was given (200 code) and the response is valid (non empty string)
        if response.status_code == 200 :
            # returns the first element of the json file to make sure it gets only one animal
            # since the api would more than 1 such as for shark it might give reef and great white
            data = response.json()
            if len(data) > 0:
                return data[0]
            else :
                print(f"    [DEBUG] return was okay, but list was empty for {name}")
                
        else :
            print(f"    [DEBUG] API error for {name} : Status Code {response.status_code}")
    except Exception as e: 
        print(f"Error searching data for {name} : {e}")
    return None
    
def get_animal_image(name):
    PEXELS_API_URL = f"https://api.pexels.com/v1/search?query={name}&per_page=1"
    try:
        response = requests.get(PEXELS_API_URL, headers = {'Authorization' : PEXELS_API_KEY})
        if response.status_code == 200:
            data = response.json()
        # runs if the photos list of the reponse contains something
            if data['photos'] :
            # returns the list labeled photos in the data, grabs the first photo, and in the src, grab the text labeled medium
                return data['photos'][0]['src']['medium']
            else :
                print(f"    [DEBUG] Pexels has no image for {name}")
        else:
            print(f"    [DEBUG] Pexels Error for {name}: Status code {response.status_code}")
    except Exception as e :
        print(f"Could not retreive image for {name} : {e}")
    return None

## review this
def get_wikipedia_summary(name):
    # This logic handles the "Tabs" issue by just grabbing the INTRO.
    try:
        # 1. Try Direct Lookup (e.g. "Lion")
        return wikipedia.summary(name, auto_suggest=True)
    except wikipedia.exceptions.PageError:
        # 2. If not found, try adding "animal" (e.g. "Okapi animal")
        try:
            return wikipedia.summary(f"{name} animal", auto_suggest=True)
        except: return None
    except wikipedia.exceptions.DisambiguationError as e:
        # 3. If confused (e.g. "Bass"), look for the animal option
        try:
            for option in e.options:
                if any(x in option.lower() for x in ['animal', 'mammal', 'fish', 'bird']):
                    return wikipedia.summary(option, auto_suggest=True)
            return wikipedia.summary(e.options[0], auto_suggest=True)
        except: return None
    except Exception: return None
    
animal_list = get_seed_list()

# get the list of animals already in the databse 
# loop through items in supabase
## GO OVER THIS
print("Fetching existing animals from database (handling pagination)...")
existing_names = set()
batch_size = 1000
start = 0

while True:
    print(f"   - Fetching rows {start} to {start + batch_size}...")
    # Fetch a batch
    response = supabase.table('animals').select('name').range(start, start + batch_size - 1).execute()
    data = response.data
    
    # Add this batch to our set
    for row in data:
        existing_names.add(row['name'])
    
    # Check if we are done
    # If we got fewer items than we asked for, we have reached the end.
    if len(data) < batch_size:
        break
        
    # Otherwise, move the start pointer forward
    start += batch_size

print(f"Database fetch complete. Found {len(existing_names)} animals total.")
missing_names = []

for name in animal_list:
    if name not in existing_names:
        missing_names.append(name)
        
total_missing = len(missing_names)
print(f"found {total_missing} missing animals.")
# create a new list that is the delta of the animal_list and that

print("Remaining animals scrape has started...")
# begin scrape for the leftover animals 
for index, animal_name in enumerate(missing_names, start = 1):
    print(f"Fetching {animal_name}")
    
    # call the helper methods to load the data and pic
    facts = get_animal_data(animal_name)
    image = get_animal_image(animal_name)
    description = get_wikipedia_summary(animal_name)
    
    # if the facts and image are not empty
    if facts and image:
        # constructing the database row
        row_data = {
           "name" : facts.get('name'),
           "habitat" : facts.get('characteristics', {}).get('habitat'),
           "diet" : facts.get('characteristics', {}).get('diet'),
           "image_url" : image, 
           "description" : description,
           "json_data" : facts
        }
        
        # insertion into supabase
        try:
            data = supabase.table('animals').upsert(row_data, on_conflict='name').execute()
            print(f"[{index}/{total_missing}] Sucessfully loaded {animal_name}")
        except Exception as e :
            print(f"[{index}/{total_missing}] Error loading {animal_name} : {e}")
        
    else :
        print(f"Missing data for {animal_name}, skipping...")
         
    time.sleep(15)
print("scrape complete !!! ")

