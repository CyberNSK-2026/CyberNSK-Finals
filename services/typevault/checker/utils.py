import random
import string
from faker import Faker
from fake_useragent import UserAgent

fake = Faker(['en_US', 'de_DE', 'fr_FR'])
ua = UserAgent()

FONT_TAGS = [
    'sans-serif', 'serif', 'monospace', 'display', 'handwriting',
    'geometric', 'humanist', 'gothic', 'art-deco', 'variable',
    'optical', 'condensed', 'extended', 'rounded', 'slab',
]

LICENSES = ['ofl', 'apache', 'cc-by', 'proprietary']

PREVIEW_TEXTS = [
    'The quick brown fox jumps over the lazy dog',
    'Pack my box with five dozen liquor jugs',
    'How vexingly quick daft zebras jump',
    'Sphinx of black quartz, judge my vow',
    'The five boxing wizards jump quickly',
    'Amazingly few discotheques provide jukeboxes',
    'Bright vixens jump dozing fowl quack',
    'Glib jocks quiz nymph to vex dwarf',
    'Waltz bad nymph for quick jigs vex',
    'Jived fox nymph grabs quick waltz',
]


def get_user_agent():
    return ua.random


def random_username():
    return fake.user_name() + '_' + rand_str(4)


def random_email(username):
    domains = ['gmail.com', 'outlook.com', 'protonmail.com', 'typevault.io']
    return f"{username}@{random.choice(domains)}"


def random_password():
    chars = string.ascii_letters + string.digits + '!@#$%'
    return ''.join(random.choices(chars, k=random.randint(12, 18)))


def random_project_name():
    styles = ['Neue', 'Pro', 'Display', 'Mono', 'Text', 'UI', 'Variable', 'Condensed']
    families = ['Grotesk', 'Grotesque', 'Sans', 'Serif', 'Gothic', 'Roman', 'Script']
    word = fake.last_name()
    return f"{word} {random.choice(styles)} {random.choice(families)}"


def random_description():
    descs = [
        'A clean variable typeface designed for editorial contexts.',
        'High-contrast display font with optical size support.',
        'Neutral sans-serif optimised for body text at small sizes.',
        'Monospaced font with programming ligatures and wide Unicode coverage.',
        'Art-deco inspired display typeface with geometric construction.',
        'Humanist sans-serif with warm strokes and excellent legibility.',
        'Technical documentation font family with tabular number support.',
        'Slab serif with balanced x-height and generous spacing.',
    ]
    return random.choice(descs)


def random_preview_text():
    return random.choice(PREVIEW_TEXTS)


def rand_str(n=8):
    return ''.join(random.choices(string.ascii_lowercase + string.digits, k=n))


def random_tags():
    return random.sample(FONT_TAGS, k=random.randint(1, 3))


def random_license():
    return random.choice(LICENSES)


def upload_font(host, token, project_id, tvf_data):
    import requests
    files = {'font': ('font.tvf', tvf_data, 'application/octet-stream')}
    headers = {'Authorization': f'Bearer {token}', 'User-Agent': get_user_agent()}
    resp = requests.post(f'http://{host}:4000/api/projects/{project_id}/fonts', files=files, headers=headers, timeout=10)
    if resp.status_code != 201:
        raise Exception(f"Font upload failed: {resp.status_code} {resp.text}")
    return resp.json()['font']['id']
