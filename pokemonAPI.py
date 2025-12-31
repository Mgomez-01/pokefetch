import requests
from rich import print


class PokemonAPI:
    def __init__(self):
        self.base_url = "https://pokeapi.co/api/v2/pokemon/"

    def fetch_pokemon_list(self, limit=20, offset=0):
        response = requests.get(f"{self.base_url}?limit={limit}&offset={offset}")
        if response.status_code == 200:
            return response.json()['results']
        else:
            return None

    def get_pokemon_data(self, pokemon_name):
        response = requests.get(f"{self.base_url}{pokemon_name.lower()}/")
        if response.status_code == 200:
            return response.json()
        else:
            return None

    def get_pokemon_image(self, pokemon_data):
        if pokemon_data:
            return pokemon_data['sprites']['front_default']
        return None


if __name__ == "__main__":
    pokemon = PokemonAPI()
    pokes = pokemon.fetch_pokemon_list()
    bbsaur = pokes[0]
    bbsaur_data = pokemon.get_pokemon_data(bbsaur['name'])
    print(pokemon.get_pokemon_image(bbsaur_data))
