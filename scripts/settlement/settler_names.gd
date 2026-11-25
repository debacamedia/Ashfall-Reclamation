class_name SettlerNames
extends RefCounted
## Names for newcomers to your settlements (Increment 33.1): over a thousand
## first names from all over, so nobody turns up as "Drifter 7". Each list
## says who the name usually belongs to, so a new settler's body matches it;
## the Either names go to either.
##
## Kept out: the story's own people (Ada Vance, Maya, Tomas, Old Jeb).

## Names that usually belong to women.
const FEMALE := [
	"Abigail", "Adaeze", "Addie", "Adela", "Adelaide", "Adriana", "Agatha", "Agnes", "Aiko", "Aileen", "Aisha",
	"Alana", "Alba", "Alejandra", "Alexa", "Alice", "Alicia", "Alina", "Alma", "Althea", "Alva", "Amaya",
	"Amber", "Amelia", "Amina", "Amira", "Amy", "Ana", "Anais", "Anastasia", "Andrea", "Angela", "Angie",
	"Anika", "Anita", "Anja", "Ann", "Anna", "Annabel", "Annie", "Antonia", "Anya", "Aphra", "April", "Ariana",
	"Ariel", "Arlene", "Astrid", "Aurora", "Ava", "Avery", "Ayla", "Aziza", "Bea", "Beatrix", "Belen", "Bella",
	"Benita", "Bernadette", "Bertha", "Beryl", "Beth", "Betty", "Beverly", "Bianca", "Billie", "Blanca",
	"Bonnie", "Brenda", "Bridget", "Brigid", "Brooke", "Bryony", "Calla", "Camila", "Camille", "Candace",
	"Cara", "Carla", "Carmen", "Carol", "Caroline", "Cassandra", "Cassie", "Catalina", "Catherine", "Cecile",
	"Cecilia", "Celeste", "Celia", "Chantal", "Charlotte", "Chiara", "Chloe", "Christa", "Cindy", "Claire",
	"Clara", "Clarice", "Claudia", "Clementine", "Colette", "Connie", "Constance", "Cora", "Coral", "Cordelia",
	"Corinne", "Cristina", "Cynthia", "Dagny", "Daisy", "Dalia", "Dana", "Daphne", "Daria", "Darla", "Dawn",
	"Deborah", "Deirdre", "Delia", "Della", "Delphine", "Denise", "Desta", "Diana", "Dina", "Dinah", "Dolores",
	"Dora", "Doreen", "Dorothy", "Dulce", "Edie", "Edith", "Edna", "Effie", "Eileen", "Elaine", "Eleanor",
	"Elena", "Eliza", "Elke", "Ella", "Ellen", "Eloise", "Elsa", "Elsie", "Elvira", "Emeline", "Emilia",
	"Emily", "Emma", "Enid", "Erica", "Erin", "Esme", "Esperanza", "Estelle", "Esther", "Ethel", "Etta",
	"Eudora", "Eugenie", "Eunice", "Eva", "Evangeline", "Eve", "Evelyn", "Faith", "Fanny", "Farah", "Fatima",
	"Fay", "Felicity", "Fern", "Fiona", "Flora", "Florence", "Frances", "Freya", "Frida", "Gabriela", "Gail",
	"Gemma", "Genevieve", "Georgia", "Geraldine", "Gertie", "Gia", "Gilda", "Gina", "Ginger", "Giselle",
	"Gladys", "Glenda", "Gloria", "Goldie", "Grace", "Greta", "Gwen", "Hadley", "Hana", "Hannah", "Harriet",
	"Hattie", "Hazel", "Heather", "Hedda", "Heidi", "Helen", "Helga", "Henrietta", "Hilda", "Hollis", "Holly",
	"Hope", "Ida", "Ilse", "Imani", "Imogen", "Ines", "Inga", "Ingrid", "Irene", "Iris", "Irma", "Isabel",
	"Isla", "Ivy", "Jacinta", "Jada", "Jade", "Jane", "Janet", "Janice", "Jasmine", "Jean", "Jemima", "Jenna",
	"Jessa", "Jill", "Joan", "Joanna", "Jocelyn", "Josephine", "Josie", "Joy", "Joyce", "Judith", "Julia",
	"Juliet", "June", "Juno", "Kaia", "Kamala", "Kara", "Karen", "Karin", "Kate", "Katya", "Kay", "Keiko",
	"Kelly", "Kendra", "Keri", "Kiara", "Kirsten", "Kitty", "Lacey", "Laila", "Lana", "Lara", "Laura", "Laurel",
	"Lavinia", "Leah", "Leila", "Lena", "Leona", "Leonie", "Lexi", "Liesel", "Lila", "Lilian", "Lily", "Linda",
	"Lindsay", "Lise", "Liza", "Lois", "Lola", "Lorna", "Lorraine", "Lottie", "Louisa", "Louise", "Lucia",
	"Lucille", "Lucy", "Luisa", "Luna", "Lydia", "Mabel", "Madeline", "Mae", "Magda", "Maggie", "Maisie",
	"Malia", "Mamie", "Mara", "Marcy", "Margaret", "Margot", "Maria", "Mariam", "Marian", "Marie", "Marina",
	"Marisol", "Marjorie", "Marla", "Marlene", "Martha", "Mathilde", "Maud", "Maura", "Maureen", "Mavis",
	"Maxine", "Meera", "Megan", "Mei", "Melanie", "Melba", "Melinda", "Mercy", "Meredith", "Mia", "Michelle",
	"Mila", "Mildred", "Millie", "Mina", "Minerva", "Miranda", "Miriam", "Moira", "Molly", "Mona", "Monica",
	"Myra", "Myrtle", "Nadia", "Nadine", "Nancy", "Naomi", "Natalia", "Nell", "Nellie", "Nessa", "Nia",
	"Nicola", "Nina", "Noelle", "Nola", "Nora", "Norma", "Octavia", "Odette", "Olga", "Olive", "Olivia", "Opal",
	"Ophelia", "Paloma", "Pamela", "Pansy", "Paola", "Patience", "Patricia", "Paula", "Paulina", "Pearl",
	"Peggy", "Penelope", "Penny", "Petra", "Philippa", "Phoebe", "Phyllis", "Pia", "Piper", "Polly", "Poppy",
	"Priscilla", "Priya", "Prudence", "Rachel", "Rae", "Ramona", "Rania", "Raquel", "Rebecca", "Regina", "Rena",
	"Renata", "Rhea", "Rhoda", "Rita", "Roberta", "Rochelle", "Romy", "Rosa", "Rosalind", "Rosamund", "Rose",
	"Rosemary", "Rosie", "Rowena", "Roxanne", "Ruby", "Ruth", "Sabina", "Sabrina", "Sadie", "Sally", "Salome",
	"Samara", "Sandra", "Sara", "Sasha", "Saskia", "Selma", "Serena", "Shana", "Sheila", "Shirley", "Sibyl",
	"Sienna", "Signe", "Silvia", "Simone", "Sina", "Sofia", "Solveig", "Sonia", "Sophie", "Stella", "Sue",
	"Sunita", "Susan", "Svetlana", "Sybil", "Sylvie", "Tabitha", "Talia", "Tamar", "Tamsin", "Tanya", "Tara",
	"Tatiana", "Tess", "Thea", "Thelma", "Theresa", "Tilda", "Tina", "Trudy", "Ursula", "Valentina", "Valerie",
	"Vanessa", "Velma", "Vera", "Verity", "Veronica", "Vesna", "Vida", "Violet", "Virginia", "Vivian", "Wanda",
	"Wendy", "Wilhelmina", "Willa", "Winifred", "Winona", "Xena", "Yara", "Yasmin", "Yelena", "Yoko", "Yolanda",
	"Yvette", "Yvonne", "Zainab", "Zara", "Zelda", "Zelie", "Zinnia", "Zita", "Zoe", "Zora", "Zuri",
]

## Names that usually belong to men.
const MALE := [
	"Aaron", "Abdul", "Abe", "Abel", "Abner", "Abram", "Adam", "Adrian", "Ahmed", "Aidan", "Akira", "Alan",
	"Albert", "Alden", "Aldo", "Alec", "Alfie", "Alfonso", "Alfred", "Ali", "Alonzo", "Alvin", "Amadou", "Amos",
	"Anders", "Andre", "Andrew", "Angus", "Ansel", "Anselm", "Anton", "Archie", "Ari", "Arlo", "Arnold",
	"Arthur", "Arturo", "Asa", "August", "Augustin", "Axel", "Barnaby", "Barney", "Barrett", "Bart", "Bashir",
	"Basil", "Baxter", "Ben", "Benedict", "Benito", "Benji", "Bennett", "Bernard", "Bert", "Bjorn", "Blaine",
	"Boris", "Bram", "Brendan", "Brian", "Bruce", "Bruno", "Bryce", "Buck", "Burt", "Byron", "Caleb", "Calvin",
	"Carl", "Carlos", "Carter", "Caspar", "Cecil", "Cedric", "Chad", "Chester", "Chidi", "Christian", "Chuck",
	"Clarence", "Claude", "Clayton", "Clement", "Cliff", "Clint", "Clyde", "Colin", "Conrad", "Cooper",
	"Cormac", "Cornelius", "Craig", "Curtis", "Cyril", "Cyrus", "Dale", "Dallas", "Damian", "Dan", "Dante",
	"Darius", "Darnell", "Darren", "Dave", "Declan", "Dennis", "Derek", "Desmond", "Dexter", "Diego", "Dimitri",
	"Dmitri", "Dominic", "Donald", "Dorian", "Doug", "Duncan", "Dwight", "Eamon", "Earl", "Eddie", "Edgar",
	"Edison", "Edmund", "Edward", "Edwin", "Elias", "Elijah", "Elliot", "Ellis", "Elmer", "Emeka", "Emil",
	"Emmett", "Enoch", "Enrique", "Enzo", "Eric", "Ernest", "Ernie", "Ethan", "Eugene", "Evan", "Ewan", "Ezra",
	"Fabian", "Farid", "Felix", "Ferdinand", "Fergus", "Fidel", "Finn", "Fletcher", "Floyd", "Francis", "Frank",
	"Franz", "Fred", "Gabe", "Gareth", "Garrett", "Gaspard", "Gavin", "Gene", "Geoff", "George", "Gerald",
	"Gideon", "Gilbert", "Giles", "Glen", "Gordon", "Grady", "Graham", "Grant", "Gregor", "Gunnar", "Gus",
	"Gustav", "Hal", "Hamish", "Hank", "Hans", "Harlan", "Harold", "Harris", "Haruto", "Harvey", "Hector",
	"Henry", "Herbert", "Herman", "Hiro", "Homer", "Horace", "Howard", "Hugh", "Hugo", "Ian", "Ibrahim",
	"Idris", "Ignatius", "Igor", "Ike", "Ira", "Isaac", "Isaiah", "Ishaan", "Ivan", "Jabari", "Jack", "Jacob",
	"Jake", "Jamal", "James", "Jared", "Jarvis", "Jasper", "Javier", "Jed", "Jeff", "Jericho", "Jerome",
	"Jethro", "Jim", "Joaquin", "Joe", "Joel", "Johan", "John", "Jonah", "Jonas", "Jorge", "Jose", "Joseph",
	"Josh", "Jude", "Julian", "Julius", "Kai", "Karl", "Kasim", "Keith", "Kellan", "Ken", "Kenji", "Kenneth",
	"Kenzo", "Kevin", "Kieran", "Kofi", "Konrad", "Kurt", "Kwame", "Lachlan", "Lamar", "Lance", "Larry", "Lars",
	"Lawrence", "Lazlo", "Leo", "Leon", "Leonard", "Leroy", "Levi", "Lewis", "Linus", "Lionel", "Lloyd",
	"Logan", "Lorenzo", "Louis", "Lucas", "Lucian", "Luis", "Luke", "Luther", "Lyle", "Mack", "Magnus",
	"Malcolm", "Malik", "Manuel", "Marcel", "Marco", "Marcus", "Mario", "Mark", "Marshall", "Martin", "Marty",
	"Mason", "Mateo", "Matt", "Maurice", "Mehmet", "Melvin", "Merle", "Micah", "Michael", "Miguel", "Miles",
	"Milo", "Mitch", "Mohammed", "Monroe", "Monty", "Mordecai", "Morris", "Moses", "Murray", "Nate", "Ned",
	"Neil", "Nelson", "Nestor", "Nick", "Nigel", "Niko", "Nikolai", "Noah", "Nolan", "Norman", "Obadiah",
	"Oliver", "Omar", "Orrin", "Orson", "Orville", "Oscar", "Osman", "Oswald", "Otis", "Owen", "Pablo", "Paddy",
	"Patrick", "Paul", "Pavel", "Pedro", "Percy", "Pete", "Phil", "Pierce", "Pierre", "Porter", "Quentin",
	"Quincy", "Rafael", "Ralph", "Ramon", "Randall", "Raoul", "Rashid", "Ray", "Raymond", "Reggie", "Reid",
	"Reuben", "Rex", "Rhys", "Ricardo", "Rich", "Rick", "Roberto", "Rocco", "Roderick", "Rodney", "Roger",
	"Roland", "Roman", "Ronan", "Roscoe", "Ross", "Rowan", "Roy", "Rudolph", "Rufus", "Rupert", "Russ",
	"Santiago", "Saul", "Scott", "Sebastian", "Seth", "Shane", "Sid", "Silas", "Simon", "Solomon", "Spencer",
	"Stan", "Stefan", "Stellan", "Sterling", "Stuart", "Sully", "Sven", "Tadeo", "Tariq", "Tate", "Ted",
	"Terrence", "Thaddeus", "Theo", "Thomas", "Tim", "Tito", "Tobias", "Tobin", "Todd", "Tom", "Tony", "Travis",
	"Trevor", "Tristan", "Troy", "Tyrone", "Ulrich", "Ulysses", "Umar", "Valentin", "Vance", "Victor", "Viktor",
	"Vincent", "Virgil", "Vlad", "Wade", "Waldo", "Walker", "Wallace", "Walter", "Warren", "Wayne", "Wendell",
	"Wesley", "Wilbur", "Wilfred", "Will", "Willis", "Winston", "Wyatt", "Xavier", "Yuri", "Yusuf", "Zachary",
	"Zane", "Zeb", "Zeke",
]

## Names for anyone.
const EITHER := [
	"Alex", "Ash", "Bailey", "Blair", "Brook", "Cameron", "Casey", "Charlie", "Dakota", "Devon", "Drew", "Eden",
	"Ellery", "Emery", "Finley", "Frankie", "Gray", "Harper", "Hayden", "Hunter", "Indigo", "Jamie", "Jesse",
	"Jody", "Jordan", "Jules", "Kendall", "Kit", "Lane", "Lee", "Lou", "Marley", "Max", "Morgan", "Noel",
	"Parker", "Pat", "Peyton", "Quinn", "Reese", "Remy", "Riley", "River", "Robin", "Rory", "Ryan", "Sage",
	"Sam", "Sawyer", "Shay", "Sidney", "Skyler", "Sloane", "Stevie", "Sunny", "Sydney", "Taylor", "Terry",
	"Toby", "Tracy", "Vic", "Wren",
]


## Every name.
static func all() -> Array:
	return FEMALE + MALE + EITHER


## 1 if `name` is a woman's, 0 a man's, -1 either (or not on the lists).
static func sex_of(name: String) -> int:
	if FEMALE.has(name):
		return 1
	if MALE.has(name):
		return 0
	return -1


## A name nobody in `used` has, picked with `rng`; "" if every one's taken.
static func pick(used: Dictionary, rng: RandomNumberGenerator = null) -> String:
	var names := all()
	var start := (rng.randi() if rng != null else randi()) % names.size()
	for i in names.size():
		var n: String = names[(start + i) % names.size()]
		if not used.has(n):
			return n
	return ""


## A name nobody in `used` has that suits a woman (`female`) or a man:
## theirs, or one for anyone. "" if every one's taken.
static func pick_for(used: Dictionary, female: bool, rng: RandomNumberGenerator = null) -> String:
	var names: Array = (FEMALE if female else MALE) + EITHER
	var start := (rng.randi() if rng != null else randi()) % names.size()
	for i in names.size():
		var n: String = names[(start + i) % names.size()]
		if not used.has(n):
			return n
	return ""
