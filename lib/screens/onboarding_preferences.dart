import 'package:flutter/material.dart';
import '../services/user_preferences.dart';
import '../services/user_prefs.dart' hide MusicLanguage;
import '../theme/app_theme.dart';
import '../widgets/liquid_background.dart';

class OnboardingPreferences extends StatefulWidget {
  final VoidCallback onComplete;
  
  const OnboardingPreferences({
    super.key,
    required this.onComplete,
  });

  @override
  State<OnboardingPreferences> createState() => _OnboardingPreferencesState();
}

class _OnboardingPreferencesState extends State<OnboardingPreferences> {
  final UserPreferences _prefs = UserPreferences();
  MusicLanguage _selectedLanguage = MusicLanguage.all;
  final Set<String> _selectedGenres = <String>{};
  final Set<String> _selectedArtists = <String>{};
  
  final List<String> _availableLanguages = [
    'All', 'Hindi', 'English', 'Spanish', 'Korean', 'Japanese',
    'Portuguese', 'French', 'Punjabi', 'Arabic', 'German', 'Italian',
    'Indonesian', 'Turkish', 'Tamil', 'Telugu', 'Russian', 'Bengali',
    'Thai', 'Filipino', 'Dutch', 'Kannada', 'Marathi',
  ];
  
  final List<String> _availableGenres = [
    'Pop', 'Rock', 'Hip Hop / Rap', 'Dance / Electronic', 'Latin',
    'R&B / Soul', 'Classical / Opera', 'Country', 'Reggae', 'K-Pop',
    'Afrobeats', 'Metal', 'Folk', 'Jazz', 'Gospel / Christian',
    'Reggaeton', 'J-Pop', 'Amapiano', 'Regional Mexican',
    'Bollywood / Indian Pop', 'Punk', 'Blues', 'Funk', 'House',
    'Techno',
  ];
  
  static const Map<String, List<String>> _artistsByLang = {
    'All': [
      'Taylor Swift', 'The Weeknd', 'Drake', 'Bad Bunny', 'BTS',
      'Arijit Singh', 'BLACKPINK', 'Ed Sheeran', 'Coldplay', 'Billie Eilish',
      'Karol G', 'Shakira', 'Anitta', 'Adele', 'A.R. Rahman',
      'Diljit Dosanjh', 'Amr Diab', 'YOASOBI', 'Rammstein', 'Måneskin',
    ],
    'Hindi': [
      'Arijit Singh', 'Shreya Ghoshal', 'A.R. Rahman', 'Pritam', 'Sonu Nigam',
      'Sunidhi Chauhan', 'Atif Aslam', 'KK', 'Vishal Dadlani', 'Shankar Mahadevan',
      'Mohit Chauhan', 'Neha Kakkar', 'Badshah', 'Yo Yo Honey Singh', 'Jubin Nautiyal',
      'Darshan Raval', 'Armaan Malik', 'Ankit Tiwari', 'Palak Muchhal', 'Monali Thakur',
      'Tulsi Kumar', 'Vishal Mishra', 'Sachet Tandon', 'Parampara Tandon', 'B Praak',
      'Amit Trivedi', 'Anuv Jain', 'Aditya Rikhari', 'Jasleen Royal', 'Prateek Kuhad',
      'Amit Mishra', 'Javed Ali', 'Rahat Fateh Ali Khan', 'Shilpa Rao', 'Rekha Bhardwaj',
      'Kavita Krishnamurti', 'Alka Yagnik', 'Udit Narayan', 'Kumar Sanu', 'Sukhwinder Singh',
      'Hariharan', 'Shaan', 'Abhijeet Bhattacharya', 'Lucky Ali', 'Kailash Kher',
      'Dhvani Bhanushali', 'King', 'Ritviz',
    ],
    'English': [
      'Taylor Swift', 'The Weeknd', 'Drake', 'Billie Eilish', 'Bruno Mars',
      'Ariana Grande', 'Rihanna', 'Justin Bieber', 'Ed Sheeran', 'Eminem',
      'Kendrick Lamar', 'Beyoncé', 'Lady Gaga', 'Adele', 'Post Malone',
      'Travis Scott', 'Kanye West', 'SZA', 'Doja Cat', 'Dua Lipa',
      'Harry Styles', 'Sabrina Carpenter', 'Olivia Rodrigo', 'The Beatles', 'Michael Jackson',
      'Coldplay', 'Imagine Dragons', 'Maroon 5', 'Linkin Park', 'OneRepublic',
      'Green Day', 'Arctic Monkeys', 'Lana Del Rey', 'Katy Perry', 'Miley Cyrus',
      'Selena Gomez', 'Justin Timberlake', 'Shawn Mendes', 'Charlie Puth', 'Sam Smith',
      'Halsey', 'Nicki Minaj', 'Cardi B', '21 Savage', 'Future',
      'Metro Boomin', 'Lil Wayne', 'Chris Brown', 'Tyler, The Creator',
    ],
    'Spanish': [
      'Bad Bunny', 'J Balvin', 'Karol G', 'Shakira', 'Daddy Yankee',
      'Ozuna', 'Rauw Alejandro', 'Anuel AA', 'Feid', 'Peso Pluma',
      'Maluma', 'Rosalía', 'Becky G', 'Don Omar', 'Nicky Jam',
      'Wisin', 'Yandel', 'Romeo Santos', 'Enrique Iglesias', 'Luis Fonsi',
      'Sebastián Yatra', 'Myke Towers', 'Mora', 'Jhayco', 'Arcángel',
      'Farruko', 'Sech', 'Eladio Carrión', 'Quevedo', 'Aitana',
      'Lola Índigo', 'Manuel Turizo', 'Camilo', 'TINI', 'María Becerra',
      'Duki', 'Bizarrap', 'Nicki Nicole', 'Cazzu', 'Trueno',
      'Natanael Cano', 'Junior H', 'Fuerza Regida', 'Grupo Frontera', 'Carín León',
      'Christian Nodal', 'Xavi', 'Danny Ocean', 'Tiago PZK',
    ],
    'Korean': [
      'BTS', 'BLACKPINK', 'Stray Kids', 'TWICE', 'SEVENTEEN',
      'NewJeans', 'IVE', 'aespa', 'LE SSERAFIM', 'ENHYPEN',
      'TXT', '(G)I-DLE', 'Red Velvet', 'EXO', 'NCT 127',
      'NCT DREAM', 'BIGBANG', 'Girls\' Generation', 'SHINee', 'Super Junior',
      'IU', 'Taeyeon', 'G-Dragon', 'ZICO', 'Jay Park',
      'PSY', 'DEAN', 'Crush', 'AKMU', 'Heize',
      'BIBI', 'Taemin', 'Jungkook', 'V', 'Jimin',
      'RM', 'SUGA', 'J-Hope', 'Jin', 'Rosé',
      'Jennie', 'Lisa', 'Jisoo', 'Sunmi', 'Chungha',
      'Hwasa', 'MAMAMOO', 'DAY6', 'ATEEZ', 'ZEROBASEONE',
    ],
    'Japanese': [
      'YOASOBI', 'Kenshi Yonezu', 'Ado', 'Fujii Kaze', 'Official HIGE DANdism',
      'King Gnu', 'LiSA', 'Aimyon', 'Mrs. GREEN APPLE', 'back number',
      'RADWIMPS', 'ONE OK ROCK', 'Hikaru Utada', 'Kyary Pamyu Pamyu', 'Perfume',
      'AKB48', 'Nogizaka46', 'Sakurazaka46', 'NiziU', 'BABYMETAL',
      'Creepy Nuts', 'Vaundy', 'Eve', 'Tatsuya Kitani', 'Yuuri',
      'tuki.', 'Da-iCE', 'SEKAI NO OWARI', 'BUMP OF CHICKEN', 'Spitz',
      'Mr. Children', 'B\'z', 'Southern All Stars', 'Masaharu Fukuyama', 'Namie Amuro',
      'Ayumi Hamasaki', 'YUI', 'Milet', 'ReoNa', 'Eir Aoi',
      'ClariS', 'Natori', 'ZUTOMAYO', 'Atarayo', 'Yorushika',
      'Superfly', 'Gen Hoshino', 'Hiroyuki Sawano', 'Mao Abe', 'Aimer',
    ],
    'Portuguese': [
      'Anitta', 'Gusttavo Lima', 'Henrique & Juliano', 'Jorge & Mateus', 'Zé Neto & Cristiano',
      'Marília Mendonça', 'Wesley Safadão', 'Luan Santana', 'Simone Mendes', 'Ivete Sangalo',
      'Ludmilla', 'Alok', 'Thiaguinho', 'Michel Teló', 'Bruno & Marrone',
      'Maiara & Maraisa', 'Matheus & Kauan', 'João Gomes', 'Zé Vaqueiro', 'Ana Castela',
      'Léo Santana', 'Gloria Groove', 'Pabllo Vittar', 'Pedro Sampaio', 'Dennis DJ',
      'MC Ryan SP', 'MC Cabelinho', 'MC Hariel', 'MC Livinho', 'Ferrugem',
      'Belo', 'Seu Jorge', 'Caetano Veloso', 'Gilberto Gil', 'Jorge Ben Jor',
      'Djavan', 'Marisa Monte', 'Tribalistas', 'Roberto Carlos', 'Amado Batista',
      'Nattan', 'Mari Fernandez', 'Zé Felipe', 'MC Daniel', 'Gustavo Mioto',
      'Simone & Simaria', 'Jão', 'Luísa Sonza', 'Melim', 'Vitor Kley',
    ],
    'French': [
      'Aya Nakamura', 'Stromae', 'GIMS', 'David Guetta', 'Indila',
      'Dadju', 'Soprano', 'Ninho', 'Jul', 'Orelsan',
      'Nekfeu', 'Booba', 'SCH', 'Niska', 'Damso',
      'Tiakola', 'Lomepal', 'Angèle', 'PNL', 'MHD',
      'Vitaa', 'Slimane', 'Louane', 'Vianney', 'Zaz',
      'Patrick Bruel', 'Mylène Farmer', 'Vanessa Paradis', 'Francis Cabrel', 'Jean-Jacques Goldman',
      'Johnny Hallyday', 'Edith Piaf', 'Charles Aznavour', 'Jacques Brel', 'Serge Gainsbourg',
      'Françoise Hardy', 'Alain Souchon', 'Julien Doré', 'Clara Luciani', 'Pomme',
      'Christine and the Queens', 'Lous and The Yakuza', 'Yseult', 'Hoshi', 'Gazo',
      'Koba LaD', 'Vald', 'Dinos', 'Mika', 'Kendji Girac',
    ],
    'Punjabi': [
      'Diljit Dosanjh', 'Karan Aujla', 'Sidhu Moose Wala', 'AP Dhillon', 'Shubh',
      'Guru Randhawa', 'Badshah', 'Yo Yo Honey Singh', 'Harrdy Sandhu', 'Amrit Maan',
      'Ammy Virk', 'B Praak', 'Jass Manak', 'Jassie Gill', 'Gippy Grewal',
      'Parmish Verma', 'Maninder Buttar', 'Ninja', 'Jordan Sandhu', 'Ranjit Bawa',
      'Sajjan Adeeb', 'Kaka', 'Prem Dhillon', 'Navaan Sandhu', 'Arjan Dhillon',
      'Gurinder Gill', 'Gur Sidhu', 'Wazir Patar', 'Talwiinder', 'Tegi Pannu',
      'Watan Sahi', 'Sunanda Sharma', 'Nimrat Khaira', 'Afsana Khan', 'Jasmin Sandlas',
      'Mika Singh', 'Sukhwinder Singh', 'Sukhbir', 'Jazzy B', 'Babbu Maan',
      'Satinder Sartaaj', 'Amrinder Gill', 'Sharry Mann', 'Kulwinder Billa', 'Gurdas Maan',
      'Surjit Khan', 'Karan Randhawa',
    ],
    'Arabic': [
      'Amr Diab', 'Nancy Ajram', 'Elissa', 'Fairuz', 'Kadim Al Sahir',
      'Sherine', 'Tamer Hosny', 'Mohamed Ramadan', 'Myriam Fares', 'Haifa Wehbe',
      'Assala Nasri', 'Majida El Roumi', 'Wael Kfoury', 'Ragheb Alama', 'Hussain Al Jassmi',
      'Balqees', 'Ahlam', 'Latifa', 'Saber Rebai', 'Samira Said',
      'Cheb Khaled', 'Cheb Mami', 'Soolking', 'Wegz', 'Marwan Pablo',
      'Afroto', 'Abyusif', 'Marwan Moussa', 'Muslim', 'Cairokee',
      'Mashrou\' Leila', 'Adonis', 'ElGrande Toto', 'Manal', 'Saad Lamjarred',
      'Douzi', 'Hatim Ammor', 'Dystinct', 'Issam', 'Lartiste',
      'Balti', 'Emel Mathlouthi', 'Souad Massi', 'Faudel', 'Rachid Taha',
      'Ramy Sabry', 'Bahaa Sultan', 'Ahmed Saad', 'Mohamed Hamaki',
    ],
    'German': [
      'Rammstein', 'Apache 207', 'CRO', 'Capital Bra', 'Luciano',
      'RAF Camora', 'Ufo361', 'Bonez MC', 'Sido', 'Bushido',
      'Shirin David', 'Nina Chuba', 'LEA', 'Mark Forster', 'Wincent Weiss',
      'Clueso', 'Casper', 'Kraftklub', 'Die Ärzte', 'Die Toten Hosen',
      'Herbert Grönemeyer', 'Nena', 'Falco', 'Peter Fox', 'Seeed',
      'Tim Bendzko', 'Johannes Oerding', 'Max Giesinger', 'Silbermond', 'Juli',
      'Wir sind Helden', 'AnnenMayKantereit', 'Provinz', 'Ski Aggu', 'Pashanim',
      'K.I.Z', 'Kollegah', 'Samra', 'Kontra K', 'Gzuz',
      'Bausa', 'Loredana', 'Elif', 'Zoe Wees', 'Alligatoah',
      'Sarah Connor', 'Die Prinzen', 'Revolverheld',
    ],
    'Italian': [
      'Måneskin', 'Laura Pausini', 'Eros Ramazzotti', 'Andrea Bocelli', 'Tiziano Ferro',
      'Jovanotti', 'Vasco Rossi', 'Ligabue', 'Ultimo', 'Mahmood',
      'Blanco', 'Lazza', 'Sfera Ebbasta', 'Geolier', 'Marracash',
      'Guè', 'Fedez', 'Achille Lauro', 'Elodie', 'Annalisa',
      'Emma', 'Alessandra Amoroso', 'Giorgia', 'Elisa', 'Arisa',
      'Marco Mengoni', 'Cesare Cremonini', 'Pinguini Tattici Nucleari', 'The Kolors', 'Negramaro',
      'Modà', 'Gigi D\'Alessio', 'Rkomi', 'Madame', 'Irama',
      'Raffaella Carrà', 'Mina', 'Adriano Celentano', 'Toto Cutugno', 'Domenico Modugno',
      'Al Bano', 'Romina Power', 'Zucchero', 'Franco Battiato', 'Fabrizio De André',
      'Lucio Dalla', 'Pino Daniele', 'Francesco De Gregori', 'Patty Pravo', 'Giusy Ferreri',
    ],
    'Indonesian': [
      'Tulus', 'NIKI', 'Rich Brian', 'Pamungkas', 'Hindia',
      'Mahalini', 'Lyodra', 'Tiara Andini', 'Rizky Febian', 'Ardhito Pramono',
      'Isyana Sarasvati', 'Raisa', 'Afgan', 'Glenn Fredly', 'NOAH',
      'Peterpan', 'Dewa 19', 'Sheila On 7', 'Nidji', 'Slank',
      'Padi', 'Fourtwnty', 'Fiersa Besari', 'Feby Putri', 'Bernadya',
      'Sal Priadi', 'Juicy Luicy', 'Reality Club', 'Barasuara', 'Yura Yunita',
      'Kunto Aji', 'Danilla', 'Marion Jola', 'Cakra Khan', 'Judika',
      'Bunga Citra Lestari', 'Andmesh', 'Virgoun', 'Nadin Amizah', 'Dere',
      'Hivi!', 'Efek Rumah Kaca', 'Endah N Rhesa', 'Payung Teduh', 'Denny Caknan',
      'Happy Asmara', 'NDX AKA',
    ],
    'Turkish': [
      'Tarkan', 'Sezen Aksu', 'Ezhel', 'Murda', 'Gülşen',
      'Hadise', 'Mabel Matiz', 'Edis', 'Simge', 'Aleyna Tilki',
      'Derya Uluğ', 'Hande Yener', 'Demet Akalın', 'Sıla', 'Sertab Erener',
      'Kenan Doğulu', 'Mustafa Sandal', 'Yalın', 'Teoman', 'Mor ve Ötesi',
      'Duman', 'maNga', 'Athena', 'Sagopa Kajmer', 'Ceza',
      'UZI', 'Lvbel C5', 'Batuflex', 'Sefo', 'Muti',
      'Ben Fero', 'Gazapizm', 'Khontkar', 'Motive', 'Güneş',
      'Zeynep Bastık', 'Melike Şahin', 'Emir Can İğrek', 'Mert Demir', 'Dolu Kadehi Ters Tut',
      'Yüzyüzeyken Konuşuruz', 'Adamlar', 'Kalben', 'Göksel', 'Ajda Pekkan',
      'Nilüfer', 'Barış Manço', 'Cem Karaca', 'Müslüm Gürses', 'İbrahim Tatlıses',
    ],
    'Tamil': [
      'Anirudh Ravichander', 'A.R. Rahman', 'Sid Sriram', 'Shweta Mohan', 'Shakthisree Gopalan',
      'G.V. Prakash Kumar', 'Harris Jayaraj', 'Yuvan Shankar Raja', 'D. Imman', 'Santhosh Narayanan',
      'Hiphop Tamizha', 'Vijay Antony', 'Sean Roldan', 'Chinmayi', 'Karthik',
      'Haricharan', 'Benny Dayal', 'Andrea Jeremiah', 'Saindhavi', 'Jonita Gandhi',
      'Pradeep Kumar', 'Govind Vasantha', 'Vivek-Mervin', 'Ghibran', 'Sam C.S.',
      'S.P. Balasubrahmanyam', 'K.S. Chithra', 'S. Janaki', 'P. Susheela', 'T.M. Soundararajan',
      'Hariharan', 'Unnikrishnan', 'Shankar Mahadevan', 'Srinivas', 'Bombay Jayashri',
      'Devan Ekambaram', 'Tippu', 'Kaber Vasuki', 'Arivu', 'Dhee',
      'Sathyaprakash', 'Rakshita Suresh', 'Kapil Kapilan', 'Sai Abhyankkar', 'A.R. Ameen',
      'Vijay Prakash',
    ],
    'Telugu': [
      'S. Thaman', 'Devi Sri Prasad', 'Anirudh Ravichander', 'Sid Sriram', 'Karthik',
      'Shreya Ghoshal', 'Chinmayi', 'Geetha Madhuri', 'Mangli', 'Ram Miriyala',
      'Armaan Malik', 'Harika Narayan', 'Kaala Bhairava', 'Rahul Sipligunj', 'Revanth',
      'Anurag Kulkarni', 'Kapil Kapilan', 'Yazin Nizar', 'Hemachandra', 'Dhanunjay',
      'Mohana Bhogaraju', 'Sunitha', 'K.S. Chithra', 'S.P. Balasubrahmanyam', 'P. Susheela',
      'Ghantasala', 'Vani Jayaram', 'K. J. Yesudas', 'Hariharan', 'R.P. Patnaik',
      'Mickey J. Meyer', 'Vivek Sagar', 'Gopi Sundar', 'Ramajogayya Sastry', 'Roll Rida',
      'Bheems Ceciroleo', 'Harshavardhan Rameshwar', 'Leon James', 'Hesham Abdul Wahab', 'Sai Charan',
      'Nutana Mohan', 'Prudhvi Chandra',
    ],
    'Russian': [
      'Miyagi & Andy Panda', 'Morgenshtern', 'Egor Kreed', 'Artik & Asti', 'HammAli & Navai',
      'Jah Khalib', 'Max Korzh', 'Basta', 'Rauf & Faik', 'JONY',
      'Zivert', 'MONATIK', 'Loboda', 'Dima Bilan', 'Philip Kirkorov',
      'Sergey Lazarev', 'Polina Gagarina', 'Nyusha', 'Klava Koka', 'Noize MC',
      'Oxxxymiron', 'Face', 'Pharaoh', 'Feduk', 'Элджей',
      'Скриптонит', 'Макс Барских', 'Cream Soda', 'IC3PEAK', 'Little Big',
      't.A.T.u.', 'Zemfira', 'Kino', 'Nautilus Pompilius', 'DDT',
      'Mumiy Troll', 'Bi-2', 'Splean', 'Leningrad', 'Ruki Vverh!',
      'Ivanushki International', 'VIA Gra', 'Mot', 'Timati', 'L\'One',
      'Andro',
    ],
    'Bengali': [
      'Arijit Singh', 'Anupam Roy', 'Shreya Ghoshal', 'Rupam Islam', 'Fossils',
      'Cactus', 'Nachiketa Chakraborty', 'Anjan Dutt', 'Kabir Suman', 'Shilajit Majumder',
      'Iman Chakraborty', 'Anindya Chatterjee', 'Chandril Bhattacharya', 'Sidhu', 'Lagnajita Chakraborty',
      'Somlata Acharyya Chowdhury', 'Timir Biswas', 'Surangana Bandyopadhyay', 'Prashmita Paul', 'Subhamita Banerjee',
      'Monali Thakur', 'Anwesha Dutta', 'Sahana Bajpaie', 'Raghav Chatterjee', 'Jojo',
      'Babul Supriyo', 'Rupankar Bagchi', 'Lopamudra Mitra', 'Surojit Chatterjee', 'Surojit O Bondhura',
      'Bhoomi', 'Lakkhichhara', 'Chandrabindoo', 'Parash Pathar', 'Moheener Ghoraguli',
      'Hemanta Mukhopadhyay', 'Manna Dey', 'Sandhya Mukherjee', 'R.D. Burman', 'Arindom Chatterjee',
      'Indraadip Das Gupta', 'Neel Dutt', 'Joy Sarkar', 'Debojit Saha', 'Shayan Chowdhury Arnob',
      'Tahsan', 'James', 'Ayub Bachchu', 'Habib Wahid',
    ],
    'Thai': [
      'Tilly Birds', '4EVE', 'MILLI', 'Jeff Satur', 'Billkin',
      'PP Krit', 'Bowkylion', 'Ink Waruntorn', 'Three Man Down', 'Bodyslam',
      'Getsunova', 'Slot Machine', 'Potato', 'Big Ass', 'Cocktail',
      'Labanoon', 'Lula', 'Palmy', 'Da Endorphine', 'Stamp Apiwat',
      'The Toys', 'Violette Wautier', 'Nont Tanont', 'NuneW', 'BUS',
      'PROXIE', 'LYKN', 'ATLAS', 'D Gerrard', 'URBOYTJ',
      'YOUNGOHM', 'F.HERO', 'Joey Phuwasit', 'Atom Chanakan', 'MEYOU',
      'Safeplanet', 'Dept', 'Whal & Dolph', 'Polycat', 'Scrubb',
      'Paradox', 'Modern Dog', 'Bird Thongchai', 'Tata Young', 'Christina Aguilar',
      'Asanee-Wasan', 'Carabao', 'Sek Loso',
    ],
    'Filipino': [
      'Sarah Geronimo', 'Moira Dela Torre', 'Zack Tabudlo', 'Ben&Ben', 'IV of Spades',
      'SB19', 'BINI', 'Eraserheads', 'Regine Velasquez', 'Lea Salonga',
      'Bamboo', 'Gary Valenciano', 'December Avenue', 'Adie', 'Arthur Nery',
      'Juan Karlos', 'Lola Amour', 'Cup of Joe', 'Hev Abi', 'Flow G',
      'Gloc-9', 'Shanti Dope', 'Al James', 'Unique Salonga', 'KZ Tandingan',
      'Yeng Constantino', 'Kitchie Nadal', 'Hale', 'Parokya ni Edgar', 'Rivermaya',
      'Kamikazee', 'Sponge Cola', 'MYMP', 'Orange & Lemons', 'Silent Sanctuary',
      'Up Dharma Down', 'The Juans', 'Autotelic', 'Rico Blanco', 'Ely Buendia',
      'Bamboo Mañalac', 'Freddie Aguilar', 'Apo Hiking Society', 'Francis M', 'Jed Madela',
      'Ogie Alcasid', 'Martin Nievera', 'Aiza Seguerra', 'Nadine Lustre',
    ],
    'Dutch': [
      'Martin Garrix', 'Tiësto', 'Armin van Buuren', 'Hardwell', 'Afrojack',
      'Nicky Romero', 'R3HAB', 'Oliver Heldens', 'Don Diablo', 'Lost Frequencies',
      'Frenna', 'Ronnie Flex', 'Lil Kleine', 'Boef', 'Snelle',
      'Davina Michelle', 'Maan', 'Froukje', 'S10', 'Suzan & Freek',
      'André Hazes', 'André Hazes Jr.', 'Guus Meeuwis', 'Marco Borsato', 'Anouk',
      'BLØF', 'Racoon', 'Kensington', 'DI-RECT', 'Doe Maar',
      'Golden Earring', 'Within Temptation', 'Epica', 'Floor Jansen', 'Duncan Laurence',
      'Antoon', 'Goldband', 'Claude', 'Joost Klein', 'Kraantje Pappie',
      'Bizzey', 'Sevn Alias', 'Josylvio', 'Sef', 'Typhoon',
      'Diggy Dex', 'Gers Pardoel', 'Acda en de Munnik', 'Nielson', 'Rondé',
    ],
    'Kannada': [
      'Rahman', 'Sonu Nigam', 'Shreya Ghoshal', 'Vijay Prakash', 'Tippu',
      'S.P. Balasubrahmanyam', 'K.S. Chithra', 'Udit Narayan', 'Kumar Sanu',
    ],
    'Malayalam': [
      'K.S. Chithra', 'M.G. Sreekumar', 'Singer Sudeep', 'Vijay Yesudas', 'Shreya Ghoshal',
    ],
    'Marathi': [
      'Ajay Atul', 'Shreya Ghoshal', 'Swapnil Bandodkar', 'Sonu Nigam', 'Aadesh Chowdhary',
    ],
  };

  List<String> get _availableArtists {
    final langName = _selectedLanguage.name;
    final key = langName[0].toUpperCase() + langName.substring(1);
    return _artistsByLang[key] ?? _artistsByLang['All']!;
  }

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final language = await _prefs.getLanguage();
    final genres = await _prefs.getGenres();
    final artists = await _prefs.getArtists();
    
    if (mounted) {
      setState(() {
        _selectedLanguage = language;
        _selectedGenres.addAll(genres);
        _selectedArtists.addAll(artists);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Let\'s personalize your music experience',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Select your preferred language, genres, and favorite artists to get tailored recommendations',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 32),
                
                // Language Selection
                _buildSectionTitle('Music Language'),
                _buildLanguageChips(),
                
                const SizedBox(height: 24),
                
                // Genre Selection
                _buildSectionTitle('Favorite Genres'),
                _buildMultiSelectChips(
                  _selectedGenres.toList(),
                  _availableGenres,
                  (selected) {
                    setState(() {
                      _selectedGenres.clear();
                      _selectedGenres.addAll(selected);
                    });
                  },
                ),
                
                const SizedBox(height: 24),
                
                // Artist Selection
                _buildSectionTitle('Favorite Artists'),
                _buildMultiSelectChips(
                  _selectedArtists.toList(),
                  _availableArtists,
                  (selected) {
                    setState(() {
                      _selectedArtists.clear();
                      _selectedArtists.addAll(selected);
                    });
                  },
                ),
                
                const SizedBox(height: 32),
                
                // Continue Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _selectedArtists.isNotEmpty || _selectedGenres.isNotEmpty || _selectedLanguage != MusicLanguage.all
                        ? () => _savePreferencesAndContinue()
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      disabledBackgroundColor:
                          Colors.white.withValues(alpha: 0.35),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Continue to Home',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.charcoal,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: AppColors.ink,
        ),
      ),
    );
  }

  Widget _buildLanguageChips() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(_availableLanguages.length, (index) {
          final lang = _availableLanguages[index];
          final isSelected = _selectedLanguage == MusicLanguage.values[index];
          return ChoiceChip(
            label: Text(lang),
            selected: isSelected,
            onSelected: (_) {
              setState(() {
                _selectedLanguage = MusicLanguage.values[index];
                _selectedArtists.clear();
              });
            },
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            selectedColor: Colors.white,
            labelStyle: TextStyle(
              color: isSelected ? AppColors.charcoal : AppColors.ink,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
            side: BorderSide(color: AppColors.glassBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          );
        }),
      ),
    );
  }

Widget _buildMultiSelectChips(
    List<String> selected,
    List<String> options,
    Function(List<String>) onChanged,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.glassBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
        children: options.map((option) {
          final isSelected = selected.contains(option);
          return FilterChip(
            label: Text(option),
            selected: isSelected,
            onSelected: (selectedBool) {
              final newSelected = List<String>.from(selected);
              if (selectedBool) {
                newSelected.add(option);
              } else {
                newSelected.remove(option);
              }
              onChanged(newSelected);
            },
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            selectedColor: Colors.white,
            labelStyle: TextStyle(
                color: isSelected ? AppColors.charcoal : AppColors.ink),
            side: const BorderSide(color: AppColors.line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          );
        }).toList(),
      ),
    ),
  );
  }

  Future<void> _savePreferencesAndContinue() async {
    await _prefs.setLanguage(_selectedLanguage);
    await _prefs.setGenres(_selectedGenres);
    await _prefs.setArtists(_selectedArtists);
    await UserPrefs().setOnboardingDone();

    widget.onComplete();
  }
}
