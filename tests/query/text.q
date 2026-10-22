## query text: numbered lines of any file, no program read (0.12).
$ text text/main.vl:6-11
// text/main.vl:6-11
6	mod util;
7	
8	use util::{
9	    twice,
10	};
11	use util::half;
$ text text/conflict.vl
// text/conflict.vl:1-8
1	// Not part of the program: a file with merge conflict markers.
2	pub fn twice(x: i64) -> i64 {
3	<<<<<<< HEAD
4	    x * 2
5	=======
6	    x + x
7	>>>>>>> other
8	}
$ text text/util.vl:5
// text/util.vl:5-5
5	pub fn half(x: i64) -> i64 {
$ text text/long.vl:240-
// text/long.vl:240-250
240	// line 240 of a long file
241	// line 241 of a long file
242	// line 242 of a long file
243	// line 243 of a long file
244	// line 244 of a long file
245	// line 245 of a long file
246	// line 246 of a long file
247	// line 247 of a long file
248	// line 248 of a long file
249	// line 249 of a long file
250	// line 250 of a long file
$ text text/long.vl:31-300
// text/long.vl:31-230
31	// line 31 of a long file
32	// line 32 of a long file
33	// line 33 of a long file
34	// line 34 of a long file
35	// line 35 of a long file
36	// line 36 of a long file
37	// line 37 of a long file
38	// line 38 of a long file
39	// line 39 of a long file
40	// line 40 of a long file
41	// line 41 of a long file
42	// line 42 of a long file
43	// line 43 of a long file
44	// line 44 of a long file
45	// line 45 of a long file
46	// line 46 of a long file
47	// line 47 of a long file
48	// line 48 of a long file
49	// line 49 of a long file
50	// line 50 of a long file
51	// line 51 of a long file
52	// line 52 of a long file
53	// line 53 of a long file
54	// line 54 of a long file
55	// line 55 of a long file
56	// line 56 of a long file
57	// line 57 of a long file
58	// line 58 of a long file
59	// line 59 of a long file
60	// line 60 of a long file
61	// line 61 of a long file
62	// line 62 of a long file
63	// line 63 of a long file
64	// line 64 of a long file
65	// line 65 of a long file
66	// line 66 of a long file
67	// line 67 of a long file
68	// line 68 of a long file
69	// line 69 of a long file
70	// line 70 of a long file
71	// line 71 of a long file
72	// line 72 of a long file
73	// line 73 of a long file
74	// line 74 of a long file
75	// line 75 of a long file
76	// line 76 of a long file
77	// line 77 of a long file
78	// line 78 of a long file
79	// line 79 of a long file
80	// line 80 of a long file
81	// line 81 of a long file
82	// line 82 of a long file
83	// line 83 of a long file
84	// line 84 of a long file
85	// line 85 of a long file
86	// line 86 of a long file
87	// line 87 of a long file
88	// line 88 of a long file
89	// line 89 of a long file
90	// line 90 of a long file
91	// line 91 of a long file
92	// line 92 of a long file
93	// line 93 of a long file
94	// line 94 of a long file
95	// line 95 of a long file
96	// line 96 of a long file
97	// line 97 of a long file
98	// line 98 of a long file
99	// line 99 of a long file
100	// line 100 of a long file
101	// line 101 of a long file
102	// line 102 of a long file
103	// line 103 of a long file
104	// line 104 of a long file
105	// line 105 of a long file
106	// line 106 of a long file
107	// line 107 of a long file
108	// line 108 of a long file
109	// line 109 of a long file
110	// line 110 of a long file
111	// line 111 of a long file
112	// line 112 of a long file
113	// line 113 of a long file
114	// line 114 of a long file
115	// line 115 of a long file
116	// line 116 of a long file
117	// line 117 of a long file
118	// line 118 of a long file
119	// line 119 of a long file
120	// line 120 of a long file
121	// line 121 of a long file
122	// line 122 of a long file
123	// line 123 of a long file
124	// line 124 of a long file
125	// line 125 of a long file
126	// line 126 of a long file
127	// line 127 of a long file
128	// line 128 of a long file
129	// line 129 of a long file
130	// line 130 of a long file
131	// line 131 of a long file
132	// line 132 of a long file
133	// line 133 of a long file
134	// line 134 of a long file
135	// line 135 of a long file
136	// line 136 of a long file
137	// line 137 of a long file
138	// line 138 of a long file
139	// line 139 of a long file
140	// line 140 of a long file
141	// line 141 of a long file
142	// line 142 of a long file
143	// line 143 of a long file
144	// line 144 of a long file
145	// line 145 of a long file
146	// line 146 of a long file
147	// line 147 of a long file
148	// line 148 of a long file
149	// line 149 of a long file
150	// line 150 of a long file
151	// line 151 of a long file
152	// line 152 of a long file
153	// line 153 of a long file
154	// line 154 of a long file
155	// line 155 of a long file
156	// line 156 of a long file
157	// line 157 of a long file
158	// line 158 of a long file
159	// line 159 of a long file
160	// line 160 of a long file
161	// line 161 of a long file
162	// line 162 of a long file
163	// line 163 of a long file
164	// line 164 of a long file
165	// line 165 of a long file
166	// line 166 of a long file
167	// line 167 of a long file
168	// line 168 of a long file
169	// line 169 of a long file
170	// line 170 of a long file
171	// line 171 of a long file
172	// line 172 of a long file
173	// line 173 of a long file
174	// line 174 of a long file
175	// line 175 of a long file
176	// line 176 of a long file
177	// line 177 of a long file
178	// line 178 of a long file
179	// line 179 of a long file
180	// line 180 of a long file
181	// line 181 of a long file
182	// line 182 of a long file
183	// line 183 of a long file
184	// line 184 of a long file
185	// line 185 of a long file
186	// line 186 of a long file
187	// line 187 of a long file
188	// line 188 of a long file
189	// line 189 of a long file
190	// line 190 of a long file
191	// line 191 of a long file
192	// line 192 of a long file
193	// line 193 of a long file
194	// line 194 of a long file
195	// line 195 of a long file
196	// line 196 of a long file
197	// line 197 of a long file
198	// line 198 of a long file
199	// line 199 of a long file
200	// line 200 of a long file
201	// line 201 of a long file
202	// line 202 of a long file
203	// line 203 of a long file
204	// line 204 of a long file
205	// line 205 of a long file
206	// line 206 of a long file
207	// line 207 of a long file
208	// line 208 of a long file
209	// line 209 of a long file
210	// line 210 of a long file
211	// line 211 of a long file
212	// line 212 of a long file
213	// line 213 of a long file
214	// line 214 of a long file
215	// line 215 of a long file
216	// line 216 of a long file
217	// line 217 of a long file
218	// line 218 of a long file
219	// line 219 of a long file
220	// line 220 of a long file
221	// line 221 of a long file
222	// line 222 of a long file
223	// line 223 of a long file
224	// line 224 of a long file
225	// line 225 of a long file
226	// line 226 of a long file
227	// line 227 of a long file
228	// line 228 of a long file
229	// line 229 of a long file
230	// line 230 of a long file
note query.truncated: lines 31-250 are 220 lines; showing 31-230
try: volec query text text/long.vl:231-250
$ text text/main.vl:40-45
error query.no-match: text/main.vl has 27 lines; no lines 40-45
try: volec query text text/main.vl:1-27
[exit 1]
$ text text/nowhere.vl
error query.no-file: cannot read 'text/nowhere.vl'
[exit 1]
$ text
error query.usage: text needs a FILE (FILE:A-B for lines A to B)
try: volec query text main.vl:1-40
[exit 2]
## show FILE: a whole small file; a long one is refused.
$ show text/util.vl
// text/util.vl:1-7
pub fn twice(x: i64) -> i64 {
    x * 2
}

pub fn half(x: i64) -> i64 {
    x / 2
}
$ show text/long.vl
error query.too-long: text/long.vl has 250 lines (show prints a file of at most 200)
try: volec query text text/long.vl:1-200
[exit 1]
## The named regions of a module.
$ show crate::use
// crate::use	text/main.vl:8-11
use util::{
    twice,
};
use util::half;
$ show crate::header crate::extern
// crate::header	text/main.vl:1-4
// A program for query text, show FILE, the named regions and
// --with-comments (tests/query/text.q).
//
// Its header comment ends here.
// crate::extern	text/main.vl:13-15
extern "C" {
    fn abs(x: i32) -> i32;
}
$ show util::header
note query.empty: no header comment in util
## --with-comments: the section comment above the item too.
$ show quad
// crate::quad	text/main.vl:19-22	effects: none
// Four times x.
fn quad(x: i64) -> i64 {
    twice(twice(x))
}
$ show quad --with-comments
// crate::quad	text/main.vl:17-22	effects: none
// ---- Arithmetic ----

// Four times x.
fn quad(x: i64) -> i64 {
    twice(twice(x))
}
## --in FILE:LINE: the item holding that line.
$ refs twice --in text/main.vl:22
# text/main.vl
21:5	call	quad	twice(twice(x))
21:11	call	quad	twice(twice(x))
$ refs twice --in text/main.vl:3
error query.bad-in: no item at text/main.vl:3
try: volec query refs twice
[exit 1]
