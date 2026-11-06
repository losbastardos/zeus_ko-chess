; ============================================================
; Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>
; Vsetky prava vyhradene / All rights reserved.
; ============================================================

; ============================================================
; hash.asm - Zobrist hashovanie pozicie
; ============================================================

%include "chess.inc"

DEFAULT REL

section .data

; Klice: 16 farieb/typov * 64 policok + side + 4x rosada + 8x en passant stlpec
global zobrist_keys
zobrist_keys:
    dq 0x950e87d7f5606615
    dq 0x2c61275c9e6b6cf8
    dq 0x1f00bca0042db923
    dq 0x6dbca290a9eab706
    dq 0x4c10a4fe30cffdda
    dq 0xf26fff4cc4fd394d
    dq 0x6814a2bc786a6d2d
    dq 0xa26b351e6c8042c5
    dq 0x54760e7fbc051c6c
    dq 0xd4c08880a5a4666d
    dq 0x29610ae0eed8f1e7
    dq 0xc34bd8e2fe5213e5
    dq 0x6c50afb6e9fb123d
    dq 0x6f28d015a2aa0b9d
    dq 0x4e385994ebac94af
    dq 0x194f9545adba52ce
    dq 0xc675ce05588f882f
    dq 0x57de8c051d4b7ef2
    dq 0xd998efd82733e933
    dq 0x6df216c33f8f3201
    dq 0x11dc6f3fcb57d5d8
    dq 0x8860a84722025e05
    dq 0x33176469aa6ef630
    dq 0x607507ebc5b864d7
    dq 0x7a2f11088d29b146
    dq 0xda10faaa6fc24b83
    dq 0x2de288f12fcb9940
    dq 0xb98937dfef041066
    dq 0xdd4b712ed355871e
    dq 0xc5b790314a2e3224
    dq 0x07fdc889fa017ed7
    dq 0x81eeadd71198bf15
    dq 0x3a46305c425a7de1
    dq 0xaaabc8d366e0440d
    dq 0x3371364fc51d1a5e
    dq 0x4763dd191ac44b70
    dq 0x016590c55646e6d0
    dq 0x0b7a6e1d81e4b9e7
    dq 0xe5a2a8bef16e981a
    dq 0x1167fba4a2927979
    dq 0x3d01ac0f1b534b87
    dq 0xd27a5f0f5532c867
    dq 0xee26cbc0358b24d3
    dq 0x9bdb39b2ca3c6a00
    dq 0x8de06fbe1a741555
    dq 0xd6257b492186c8b5
    dq 0xdee7539c539445f3
    dq 0x4307513f1ec1b0b1
    dq 0x1d790bcaeffd4d2d
    dq 0xde18f50a43cf423a
    dq 0xd36c78ab3537a844
    dq 0x64b5e3f81a293b3b
    dq 0xe8eef3d67646f8a9
    dq 0xa88d379db047719d
    dq 0xf177d49f03ddc3bf
    dq 0xa745fdd552965bca
    dq 0xd0b6a46a7048daca
    dq 0xfce79398852e0400
    dq 0x760c9b756320dbe3
    dq 0x4e52b41980271e94
    dq 0x293f65848aa18f43
    dq 0x520e015e444ed0f2
    dq 0x793ff51bb0baf029
    dq 0x7ad955568f86a26a
    dq 0x1c720603ec8602d9
    dq 0xd08e7565d487d342
    dq 0x310288290b43dbfb
    dq 0xd50ca99e8e59ea07
    dq 0x6c24e82c6dbbac73
    dq 0xb7a13dce8e4595df
    dq 0xe91b8ec1f011e633
    dq 0x9293bf4aed9a76b9
    dq 0x75c33f8fcb8031fe
    dq 0x1e7c31d385989296
    dq 0x5574e314ddfc20fe
    dq 0xd17dad339930e76e
    dq 0xacfbba2a3f8666ee
    dq 0xa4e307830deef007
    dq 0x8fcd110ce94f47b0
    dq 0xe1660a4195d74835
    dq 0xd6d91d39227d512d
    dq 0x2abb018969cbe6eb
    dq 0x09cea2a86a921843
    dq 0x3fe9e76493a8b5d8
    dq 0x602f8e87d16bc8be
    dq 0xe376bd78d7304cb6
    dq 0x748781c961ef7dfc
    dq 0xff5e243c496a590b
    dq 0x089934a93d71d058
    dq 0x3deadc7d1d2e1a2e
    dq 0xe443e6031233f1e0
    dq 0x5ab59d10b4a20569
    dq 0x658141e73ede6f12
    dq 0xf5d46d8127762b7b
    dq 0xad1dd1408b87cfcb
    dq 0xf9afa64760083c7d
    dq 0xb7a68aa8611b9b59
    dq 0xd828056ea86fc09c
    dq 0x1c0ae9a87893032b
    dq 0x34c8a05ca34be96a
    dq 0xc966aed65a10eeaf
    dq 0x6b7e21f0921082df
    dq 0x6e5d9a3007c331a3
    dq 0x3a0806a754f57983
    dq 0x0a07a198f7767fd6
    dq 0xf0723a8383f43dc4
    dq 0xfb65e62582414d3f
    dq 0x504516f2106025b5
    dq 0xa0d72f15feb859eb
    dq 0x115600523ea6fb4d
    dq 0x1be3ae0c3b97b6c9
    dq 0x5fe2b11364b97756
    dq 0x5a8a944097dea5e8
    dq 0xc330642bbf1317f8
    dq 0xf0b02956ff594f79
    dq 0xa4002d902b1b1e58
    dq 0xba351d1d2912ab9f
    dq 0x56761e8879073c59
    dq 0x3912a0fca373e01b
    dq 0xec004af1d0efd4ff
    dq 0x8919551203d33d87
    dq 0x64f85da91a44dfa0
    dq 0x21d287d8efb4cad1
    dq 0x1732b75d08d75496
    dq 0x27623245c6251a5c
    dq 0x987abb69ec5093da
    dq 0xea45cdaf628e21c8
    dq 0x0272834f4d8a9084
    dq 0xab699ad2c231185b
    dq 0x6ff327f4119ee914
    dq 0x6b06b34098ca4c3f
    dq 0x725461191d5d7302
    dq 0x511173b251af8015
    dq 0xebbfbb2bc3846ece
    dq 0xed8b79ed1d74a080
    dq 0x9736b29f0b03d0e1
    dq 0xceaf0df42de3540c
    dq 0x576c473aecbeb26f
    dq 0x6782e42f80a0f27d
    dq 0xf39f015e2cafb91c
    dq 0x293c27e425e74da2
    dq 0x1a18b9b1c2c8b502
    dq 0x731535ecb7b2a53b
    dq 0x4f7d9b08c0f76e59
    dq 0x3e115e3e75118be1
    dq 0x689db40cdd801db4
    dq 0x399246294d8fc042
    dq 0xc018ee73ff8f5cff
    dq 0xa364f1b057f4865e
    dq 0xbd5993b1f9f2dce0
    dq 0x1fb37062a68f65c1
    dq 0x2a5f2d8aca707a92
    dq 0x3ff1295c1d296c14
    dq 0x4ea7feaa1455fcad
    dq 0xb484b8d3f354db28
    dq 0xdef5e3507a2ee034
    dq 0x1a46b9e3a2663f03
    dq 0x5665aca3177d70d6
    dq 0x36a208e01b1b4ee3
    dq 0x00822ed4e33a0336
    dq 0x9d3bd30e22749e54
    dq 0x703666d165265fe5
    dq 0xebe4418c6286ef71
    dq 0xe07f915527fcb0f2
    dq 0xcfedc87950868c9c
    dq 0x95825097784ecbbb
    dq 0x106572c92038d12e
    dq 0x79b713272176822e
    dq 0x810287a90cffae31
    dq 0x7c8f5a44b03c1008
    dq 0x113167635255aa79
    dq 0x9f0600356aab79e5
    dq 0x559ccfb8c80ce420
    dq 0x33fc57dd263695f9
    dq 0xc2299345df0b305d
    dq 0x3519cb88dac97abb
    dq 0xed1137eb3e5e1046
    dq 0x22b6ce988e5e8733
    dq 0xe3bd76bf57cec991
    dq 0x402117a53e2681d1
    dq 0xeee4852d330c2394
    dq 0x854773512f3334bf
    dq 0xcfe680854c95ea72
    dq 0xe3aab3ddc209f79d
    dq 0xa2842cb2fb44c6a2
    dq 0x32442b01a0f4dd5a
    dq 0xe5fbc6d02bd667d6
    dq 0x343c5382621d123a
    dq 0x6cb5b7d2782a1890
    dq 0xef04a4a598411feb
    dq 0x31afaa01fdc2dbd7
    dq 0x5762032f27aa949b
    dq 0x332508b2d1c97795
    dq 0xb93ad7dfcba7ddcd
    dq 0x4930986a215c9b8b
    dq 0x3caf648a3fe36a17
    dq 0x4e1309a0fc447a7f
    dq 0x019d6ac5fe7f773e
    dq 0x637118bb0b0e773c
    dq 0xba17e7bd0a7a8b0c
    dq 0x20b9122fca694c79
    dq 0xb0773e1b8ea50117
    dq 0xa544b6d2cf823377
    dq 0x3e2e21041529057c
    dq 0x01d6aedaa22e88e8
    dq 0x673bb9153bc7eead
    dq 0xf332dec5058c062b
    dq 0x802df2eef9537531
    dq 0x26dd7c451562a836
    dq 0x0c72e5f1f03cde37
    dq 0xeae27c2bcf28335a
    dq 0x9482faca03ac665d
    dq 0x6774a90031d2ba09
    dq 0xe6b37c203fbd6d30
    dq 0xc958935b157304b1
    dq 0x9ef80467a8e636c6
    dq 0xa7d73426f0aee715
    dq 0x4ac05557bdca343f
    dq 0x65c2195389de9f30
    dq 0x7b4afcc0a8108c27
    dq 0x938f35b2dc04bbfc
    dq 0x642e484600cdfa67
    dq 0x890c62927989d7e6
    dq 0x11d0bc174b47a18b
    dq 0xd0ae2b468f227e2f
    dq 0xb9f409d40d3832c1
    dq 0xa37579c44c86abf9
    dq 0xcc69f35beecff786
    dq 0x3cd64d14ac521437
    dq 0xb860c5a45b4be237
    dq 0x3d1791cf2b9550bc
    dq 0x4c5b4726a89a476e
    dq 0x12e2992b24380fb6
    dq 0x0fb88164ccc14927
    dq 0x9dca0bdcdd3a68c5
    dq 0xeb0e37f4d6290f03
    dq 0x0e8936d8133fee34
    dq 0x2e778e78671eaa35
    dq 0x616eb2a9fb09b28d
    dq 0xaac0c22e5d235cab
    dq 0xad4cf62c94a4f317
    dq 0xcf3b5ee99ca944bb
    dq 0xc1f007cd2413872a
    dq 0x18fde7a7091e9247
    dq 0xe8ed59599a0e9c30
    dq 0xb036bade9e716b3d
    dq 0x92852160c8b912b1
    dq 0x59ad98498ff5b11b
    dq 0xd41339c948a6e7cb
    dq 0x3c79a0009f140b4e
    dq 0x34186cdd3c3c5140
    dq 0x919b6a673343fd70
    dq 0xbab5120ef942a0f6
    dq 0x3c8016d006c1ec71
    dq 0x28e208906796f59f
    dq 0xfbd9efbb76c9773a
    dq 0xf3d6da5c3df5a974
    dq 0x22a49f27fef4ca54
    dq 0x2935e72533e01f5c
    dq 0xe36fc27336a1483c
    dq 0x91a6821dd6d9ac33
    dq 0x7328a7776b70929b
    dq 0x1069a2114ba0d198
    dq 0xb1bbd78722e9dde7
    dq 0xefb27ceed7b68265
    dq 0x657782da9744782b
    dq 0x31eed1a700b6ec29
    dq 0x9a1e2d7b24252495
    dq 0xaa1a3b8e0336d241
    dq 0x3e96c928f239c6e8
    dq 0xd977bc4f68576763
    dq 0xf5c1e0efc83c98ee
    dq 0x4788ae323e2a32d8
    dq 0x7a5286e53a968735
    dq 0x10fb01d7cb2aaf84
    dq 0xe18e124e9a1938b3
    dq 0x31ee89b3b4eaa601
    dq 0x94cc7b72fc3196cd
    dq 0x56ed6af7e42c893a
    dq 0xf6db24bb16f42afe
    dq 0xbf83c8b771312e2d
    dq 0x38a2d999a2f70ca6
    dq 0xcd2f2acc0bcd93bb
    dq 0xa4eaa48c2f25b957
    dq 0x1765dee27d9f4de0
    dq 0x31546df37cf45beb
    dq 0x53f901828270094c
    dq 0x16ec812185e2bf7a
    dq 0xbdca6ba34ba3aea5
    dq 0x18d61c61f5817f08
    dq 0xa404755e3f48dad8
    dq 0x5cf7913a8a83b801
    dq 0xbf30024eaf8c988d
    dq 0xc78c11e872e68302
    dq 0xe07055c2c6066ea3
    dq 0xc701922a21d50422
    dq 0x0c9f02c0c331631c
    dq 0x4b3ea9272944860f
    dq 0x8d2ed5bfb86af1e9
    dq 0x35db7aa4e6aa9fbe
    dq 0xcc3727a535e6f183
    dq 0xc10aff86552d7c5c
    dq 0xdf44645f9b5c5903
    dq 0xa4a83317c9035f5a
    dq 0xb437842a423fdaf1
    dq 0x23c479391f63d5bb
    dq 0x7a912fe00240ea41
    dq 0xa4db234279adab48
    dq 0xb26d94de181f3b48
    dq 0x4bc2e4b741387e39
    dq 0x55261cfd037b77e8
    dq 0x2122f418436d6e1a
    dq 0x2c957f868af483d9
    dq 0x7dca60ccfd2c7151
    dq 0x26f738bd308cc6db
    dq 0xdfea4290cd71f52c
    dq 0x2d1993c9ce8f5e14
    dq 0xf2d6c88d04534ef9
    dq 0x5a2b562d904d0fe9
    dq 0x010032b7ad22b118
    dq 0x2505f1ef65cbae4a
    dq 0x11b72d22ffcc0a87
    dq 0xa41c340e7759c478
    dq 0xd698449e6269066f
    dq 0x42b3df0850922066
    dq 0x3cb02a3a71de26fb
    dq 0xc6ca07bd2aa14eb1
    dq 0x42080a2027661517
    dq 0xe77e24b969f3f5f4
    dq 0x26ea3f3b235ece3e
    dq 0x14f7f8012b541659
    dq 0x80d40fb498de2acf
    dq 0xbfa8a3cb4e36760a
    dq 0x1ae9ecd25b9a5152
    dq 0x8725bd0145af9d6c
    dq 0xfe3c3e0dc0fc4640
    dq 0x366aaa39f86e6c82
    dq 0xdc138f3a543c17b2
    dq 0xbe4e97469d40ecf0
    dq 0x79f3fac8af80189e
    dq 0x5731c06ebcd2155a
    dq 0x758062e1881767ea
    dq 0x32f1d920115fff4d
    dq 0xd3e0f093e39329c7
    dq 0x6cdd15e527979949
    dq 0x6fa8ec9eb43d610a
    dq 0xbd9923d1c63c3595
    dq 0x91b97205f19348ce
    dq 0xc91bf4c95965d7b9
    dq 0x3c388795394125c6
    dq 0xdbeaf8a6be12f2dc
    dq 0xa3f1a393915b030d
    dq 0x43585d602408d6de
    dq 0xcf58e839be4bb684
    dq 0x46538acb32684cc8
    dq 0x8711d60ebb559d50
    dq 0xaccf3b1060f4ed26
    dq 0xc699e61e3bcd780b
    dq 0xeb29cdab8817da35
    dq 0xac2b847c83c7be14
    dq 0x4c3ded8427917a26
    dq 0x8412b36b8f3f38e2
    dq 0x15b12e36b7bb1b1b
    dq 0x1534b0d770ab8e57
    dq 0x625cf3b87dfc4312
    dq 0xac0bd149f4a29076
    dq 0x1441b6a6e85b171d
    dq 0xc2be8bb9568c3218
    dq 0xe811e7a0b5df8375
    dq 0x019a7a73cb203d95
    dq 0xddd78ddba912675f
    dq 0xfa657641929374e5
    dq 0x5389bc8fa0c7f735
    dq 0x5b6fc09db4c58837
    dq 0x1c738f5e6311cb53
    dq 0xca5d911b09f9b17a
    dq 0xa1d5e3902d85c825
    dq 0x0862e48ca625a343
    dq 0x617ee52d421cf8b8
    dq 0x63419f53ae693e7a
    dq 0x0ff9318c004a1855
    dq 0xec592941c58fbb0c
    dq 0xd69c69a74256da1e
    dq 0x2ada33cfcf04413b
    dq 0x407b4a4e5ce4c4dd
    dq 0x4b6bb141d06936ea
    dq 0x007ea19eab12de70
    dq 0x692ad243adcf26b4
    dq 0x46c4fe73cebc6e85
    dq 0xf6b750a7bf119e74
    dq 0xd2487bf388faf600
    dq 0xfbeb9bdbc264a69d
    dq 0x388fdb6c77eaf731
    dq 0xde911d76425de5c9
    dq 0x0f4723d3813756fe
    dq 0x4a6491ea8586f256
    dq 0x4c7414f797360345
    dq 0x480666cc4c47407c
    dq 0x0b58c2a170b43162
    dq 0xfffbb8ac65112dd7
    dq 0x65e6f0890ad48d4e
    dq 0x330b13396cf097e5
    dq 0x6e4a7d9a54920ff5
    dq 0x07013891ba146906
    dq 0x52c9b6c0af280f5f
    dq 0xef2ae3f8fd30ac31
    dq 0xfb285bc775ddec36
    dq 0x29e9245e026f30cf
    dq 0x6b31e218e084a356
    dq 0x5dababfd0d1ce01f
    dq 0x4f65135b4a584ca4
    dq 0x4d0098666139ac91
    dq 0x124910222a5eb3e4
    dq 0x62d348a74128c686
    dq 0xdcaf10aa24c741c3
    dq 0xe42f471add15d5d3
    dq 0x4570cbd34a642192
    dq 0xb96c1b32e1e3f183
    dq 0x42e54e056c1db617
    dq 0x558a2898fe1902b6
    dq 0x9de00460a7e50664
    dq 0x72e021a839a927dd
    dq 0x5bed06f98494a553
    dq 0xdc6925e319646ee2
    dq 0x68f420ab9a248385
    dq 0x50bed195cccbfcd1
    dq 0x01cb34eebf810d7e
    dq 0xd3c1fa2507618d67
    dq 0x7f764ca1384e1792
    dq 0x46e589adbcd9efdf
    dq 0x3ba580666d0ef890
    dq 0xd8ed2af1e6e2a938
    dq 0xbcb960ef6cbab523
    dq 0x2c2c89add996f650
    dq 0x54c8569e29e00949
    dq 0x9cfbeb7342a264ef
    dq 0x2a8da4f81f024247
    dq 0x060f51b49dcdb079
    dq 0x955df2e12373a42e
    dq 0xa2493869e9dadf00
    dq 0x5d4f01e4b4c11672
    dq 0xd5821be7ab73ae7a
    dq 0x6af5533e14e0d997
    dq 0x8b6ee9e81a7cba91
    dq 0x2c5f0138a685cfaf
    dq 0xdc168165b405662b
    dq 0xf42c6ea68e940f03
    dq 0xb8c1508db896db64
    dq 0xe69e8e31a3ad1ecc
    dq 0x9a84fd1bb42dc8f0
    dq 0xb5090e6d99e77bb4
    dq 0x2fd8a3b2e6e58652
    dq 0xe8f0279aa92d19c2
    dq 0xc25b8e1a9d88f18d
    dq 0x60f7ebe081a1091e
    dq 0x3bde37ff5a79b8b4
    dq 0x1a6437d03002c888
    dq 0x0867c62c2ad4310b
    dq 0x376fb5506c9f0093
    dq 0xf219ecc4568bb0ac
    dq 0xd2ef145fff9ef2ed
    dq 0x6c6fb1038c56b2cd
    dq 0x5822181913bccd6e
    dq 0xbe4ec7ad518a6a37
    dq 0x5ae874748e225684
    dq 0x572831e13840133e
    dq 0x301432c51cd1a9b2
    dq 0xc3af1ff482a4dd39
    dq 0xd8e35f79b996b603
    dq 0xfcf2477557457206
    dq 0x7ae609bd1a164402
    dq 0x2dba7d33576fe819
    dq 0xc96273a2f1042100
    dq 0x0dc1aa139197837d
    dq 0x5b6de579a157436d
    dq 0x32e0ae1a43cf06b9
    dq 0x7e048f28349a6e74
    dq 0xa44584a5fd00ede1
    dq 0x82702172bb424a97
    dq 0x55cfaf7f4785e8c6
    dq 0x46c909ca6740a1d2
    dq 0xe779a4e3fba78bc5
    dq 0xf32b26b9a55ff9ed
    dq 0xa0ebf3b9c13bf1e8
    dq 0x35b0db5e86d136fc
    dq 0xfea726a245c93cbb
    dq 0x2534ff4601d4283f
    dq 0xd698bd99f435ece5
    dq 0x0747c987820ff21f
    dq 0xcc9886d370342492
    dq 0xcc073fae368aa026
    dq 0xbbc5a4a55b5b3ad4
    dq 0x1a26f01060844a50
    dq 0x9267b5b558ededf1
    dq 0xaf71f2b56438fa8b
    dq 0x43054ffa7e732590
    dq 0xbe1f5e0e3e15a005
    dq 0x5d5a4faa1ccc4982
    dq 0x4cdf4c9072da05f8
    dq 0x78641829ead96262
    dq 0xc781fc1a9dfc9808
    dq 0x9013d7f40c1c08f5
    dq 0x017283141afb22c9
    dq 0xa6f0d0f82d74a5a5
    dq 0x679be4393d112b91
    dq 0x8d51f571b677657d
    dq 0x90caef1225e345ed
    dq 0x2bdbd23bd6e337b3
    dq 0xea0345a7135a758f
    dq 0xf64c7c2446c00f12
    dq 0xd63b93e3639da6fe
    dq 0x42fa9a409e2c2e93
    dq 0xc0a96d2f1e1e6ab0
    dq 0xfbf8b48e4e9ec93f
    dq 0xe021394ad10ed2b2
    dq 0xfae299d18960fe6d
    dq 0x9bdd5113e16a00c5
    dq 0x43e667c86158e5aa
    dq 0x508d8ee58c6f0564
    dq 0xcd8fcd15202d200b
    dq 0x60455559dd2a943e
    dq 0xedbb511842d681ee
    dq 0x3d302786362b079e
    dq 0x8104180d3b28a528
    dq 0x3e9a1fd68245b874
    dq 0xb1d199f8e16fa5f2
    dq 0x9abce3dc89d40703
    dq 0xd7f08858761cdd71
    dq 0x01fc4b4627a2f440
    dq 0x00e7c918c5a1e003
    dq 0x85044622e141ca0e
    dq 0xe5871a0676aa8803
    dq 0x3848db08de214095
    dq 0x7c2ab555e5838835
    dq 0x9271554fd45a2226
    dq 0x1469231695eda9d3
    dq 0xa6911818dc2951fe
    dq 0x6df9d61e9424b92d
    dq 0x0794d015d94ac008
    dq 0x6eed9b3d3caa1af0
    dq 0x82ca9a76dc280ac6
    dq 0xb482adcd8961211a
    dq 0x64996a227627a130
    dq 0x12b91d68dacbddf7
    dq 0xb352f1d6d312b042
    dq 0x9c423351b2f684fb
    dq 0xd037bc75c0309553
    dq 0x993619887b74f720
    dq 0xfa66baee32c88923
    dq 0xacfd995f5ad69403
    dq 0xe63186fe667b0b75
    dq 0x3b5cc4baf7b7e95c
    dq 0xcfb22312100b1582
    dq 0xdab41631b81fe1af
    dq 0x6a54d63329049e27
    dq 0xbbbe7690a5f89335
    dq 0x067e1381854c54a8
    dq 0x1bb4756c8eb9b734
    dq 0xfaa685701835de82
    dq 0x3198f7f88a358e35
    dq 0x50e122b5bc193ec4
    dq 0xe0f810feda9ada14
    dq 0xd50c4068ddeee4c0
    dq 0x9e02c9d781cb7c88
    dq 0x90973d6e4ea6735e
    dq 0xf18fb01e4aa6ca15
    dq 0x8251b6767b312a3e
    dq 0x436bcae8969602cf
    dq 0xab8473367d1b42c6
    dq 0x09cba6282242ce96
    dq 0x2d362270435b5a62
    dq 0x66f08f8a9cc5e319
    dq 0xc0df3593fa11c835
    dq 0x2272f82e0d1d16d2
    dq 0x760713b701a3d349
    dq 0x3860291468b7c0c8
    dq 0x9bd9df97df2b5ada
    dq 0xac5dfc50ea3e5eb2
    dq 0x1565ebb90307aca8
    dq 0x615c2bdee59065b1
    dq 0x1254c8ff04997762
    dq 0x2b627185d87d7b06
    dq 0xddcec8dd66beb167
    dq 0x5c52caf3b645fed7
    dq 0x7cbac2242e343761
    dq 0x46edc694b1b2ff00
    dq 0x598c132152285a8d
    dq 0xb343bbfc34959810
    dq 0xf24a7b312d02ca06
    dq 0xf12ffe084e137b0f
    dq 0x78b77ea4f4694315
    dq 0x3d5d1f29d524a072
    dq 0x882a6de055c347bc
    dq 0x6411eceb2b029754
    dq 0x0ef79f17ea223aba
    dq 0x9a615ea1a844493e
    dq 0xa424ff44a168663d
    dq 0xde48957b43209218
    dq 0x10d2667c5fdec332
    dq 0x66bede83f58542a7
    dq 0xd5ed5da7d9fa2314
    dq 0x024c2d43c67ca18a
    dq 0xde601f5e480ac1bb
    dq 0x0725ac7a33125bf2
    dq 0xc5ee1e64eae54057
    dq 0x0dcae35beccc54eb
    dq 0xe8cfa75ba2ee4804
    dq 0x5313ffe0fc20d218
    dq 0x35be64ccd0d7346f
    dq 0x5ff68b4455086f8d
    dq 0x633c00748392c25e
    dq 0x8170aea6355b9ac3
    dq 0x7800979fc4eb1980
    dq 0x98e206ecb3623c0a
    dq 0xacd40783da42b32d
    dq 0x5e8c1e220258d338
    dq 0x6e2564807592237f
    dq 0xef2f7e360132b1ec
    dq 0x9b4e092b7cd22b49
    dq 0x883781ffc4b37f33
    dq 0xa13020bc6750eadf
    dq 0x84a5732248db8018
    dq 0x774cac51b4273bf4
    dq 0xaf5949344dfceda9
    dq 0x8f7bdc02090116bc
    dq 0x0d56371e7a6f1373
    dq 0x5a85e64812c5547d
    dq 0x2229c029894a1f5e
    dq 0x31f22effdc712e90
    dq 0x74ad1980b3a228d4
    dq 0x44f060a13239d2f9
    dq 0x79b97ac4d10347ca
    dq 0x1451bfe78b4c6dc2
    dq 0x6a5ae9fce0872330
    dq 0xfec53cd09359075a
    dq 0x5caa179f3beb1010
    dq 0xf4eb7fd73fe2a9e0
    dq 0x7a86d541b1194301
    dq 0x03b077eb402e3abc
    dq 0x7f38783547a781b4
    dq 0x01bc6ee497c0b7b0
    dq 0x4fac144cf6b24e41
    dq 0x7ce72167e030c0ab
    dq 0xefa3bab5a8a7b488
    dq 0x83552eef9fe22ecb
    dq 0x3e059f5f2cc9c561
    dq 0x81b097c664c0324e
    dq 0xc44ede664ed30ce3
    dq 0x29d68ac39f13984f
    dq 0x1f14b9a88a18005c
    dq 0xe0a1e0337b396658
    dq 0xd3e8c6178d8d3159
    dq 0xd650db79b6dbab5e
    dq 0x3f798b1f01802a2f
    dq 0x22ef3ee16ab72fa7
    dq 0x4fea9b5c9212fe9c
    dq 0x96de49b064160ca1
    dq 0xb048ae19d1500b28
    dq 0x3940e18a406693c9
    dq 0x9382194fb5497faf
    dq 0x723cd070376b6725
    dq 0x6be0708c69fbb07f
    dq 0x63a77d32db2cc092
    dq 0x1a700e997de1c426
    dq 0x1b755b678e6d02fb
    dq 0x7ffcef9f22a3f6f2
    dq 0x34238f6beafb4766
    dq 0xb112a66f00eb7e8a
    dq 0xac32163bafeb478d
    dq 0xe16e68f143611a32
    dq 0xc3d9725eff5d7b70
    dq 0x5702d16710d128c7
    dq 0x6a3952e0af7dbaca
    dq 0xf369ab22c0f76e1d
    dq 0x15e5c8fcc2e81253
    dq 0x568c0427a8a1e9ec
    dq 0xe3eab26637deb1c2
    dq 0xface7d481ce5248b
    dq 0x1f8c804234eaa02a
    dq 0x3f3cecbcc0a07117
    dq 0x5d1942c2935a35e6
    dq 0x5f5c081a5829d472
    dq 0x8b14a9ea722b64c3
    dq 0xb583c9565540f42f
    dq 0x4159923400c9c479
    dq 0xefc4614bbc2196d4
    dq 0x0f5f5b891704d4c4
    dq 0xee5058176d455b25
    dq 0xe2f717bd9cf695b9
    dq 0xa14a1c9de6dc48f1
    dq 0x933ab203cb90e9bc
    dq 0xa06e6cd8072280c7
    dq 0xceac93893c4ab102
    dq 0x34601ed98d25ac2b
    dq 0xc704ac6cd39703c6
    dq 0xb1c5944bb406e3e9
    dq 0x90454a2f326d4a1d
    dq 0xcba78c16aab4b70e
    dq 0x0db607222d9213a7
    dq 0xb8bbd375a4d2ba5f
    dq 0x6b96ee41f433ea66
    dq 0x121d7717cf5587b5
    dq 0x069ff6674cf3de26
    dq 0xd94e2df9746a6589
    dq 0xace8c46722862606
    dq 0x5aa4f3fcc56380cf
    dq 0xa0b364aa68d61017
    dq 0xc39ed6d8bc57e783
    dq 0xa6ee9a6282b5c772
    dq 0xbc6106183cdb5c29
    dq 0xa9c43628ebe5b14f
    dq 0x37f2c204e3ced87a
    dq 0x49fb3f942c30b4f5
    dq 0x9482fc2b7d4ade0a
    dq 0xfa06cd9597c7ab60
    dq 0xc3bbf45de0d2fd0c
    dq 0x5c28a18b9bf716cb
    dq 0xf52bcf44dfd92f95
    dq 0x80e11783b9ec87eb
    dq 0x38d35ef0003d7e34
    dq 0x8e9aeb1adc586314
    dq 0xf4a51eea589ef3c1
    dq 0x32d1b9d49774ecbf
    dq 0x1cd410bf60825dc3
    dq 0xa259302c6e2ca568
    dq 0xf4f95834b4d52f06
    dq 0xac3a3a5e2dff5160
    dq 0x4120ecb0b4739680
    dq 0x8a77490e5c3f573e
    dq 0x512d6d91f422567d
    dq 0xe9af8c1a26e721a7
    dq 0x8007c6f2f1141bc5
    dq 0x999f642a1025ab34
    dq 0x687fb6afcc41ca6a
    dq 0x5d1fbdf4a3117dfc
    dq 0x5514103e59220436
    dq 0x164b447535de5177
    dq 0xf32b49b05b5daf21
    dq 0xb990e813002b4098
    dq 0xee4027dcbfa1e989
    dq 0x34a11d5971344d53
    dq 0x4f222f6d517c15f6
    dq 0x82434cec47fc20b2
    dq 0x8ad78a846f3e74c8
    dq 0x52f2ff250f0950b6
    dq 0xaba808230469d82a
    dq 0x2d88ced98b14d0e0
    dq 0xb8216e875013e541
    dq 0x3bfa4e58eef5db31
    dq 0x55128cec70f74c1a
    dq 0x9996b350cb00f676
    dq 0x2d0cecd558519c00
    dq 0x54cf6ebd5665314c
    dq 0xc9e3c7af7285b890
    dq 0x22e724d384b4aba7
    dq 0x2b0b00e2d662ee2f
    dq 0x3f68a927c18c77a3
    dq 0x42db26568400e36d
    dq 0xb9b53f971b7a6872
    dq 0x40d05cd07c5a3dd6
    dq 0xb2999dcc33bd5047
    dq 0x6c5b5b3b6e4af5ba
    dq 0x9c2082e7609cb58f
    dq 0x1787a4f35fdbecb9
    dq 0x8c18438b0f3d69ce
    dq 0xe9dba0ec40c1c9d2
    dq 0x70d6e9ef68218d02
    dq 0x89a9806d1b1cde82
    dq 0x56906aaad9cd68cd
    dq 0x62e6edc78a746561
    dq 0xd1fc9804c0ab80a8
    dq 0x36c47d2d153c7fe5
    dq 0x1bf668ec918662c9
    dq 0x223093ba7813f2a7
    dq 0xd2b194c719b3e9db
    dq 0xa7a4a436ff302c27
    dq 0x518a882b19b26350
    dq 0x77c91f18822bc713
    dq 0x4bfff66dd145468b
    dq 0x0444fc3373fc1ed0
    dq 0x62ab55780347931b
    dq 0x27194532f3766fdb
    dq 0x268b58601c57a5e9
    dq 0x6dcd2134dea1bc25
    dq 0x32b6b7d25e840974
    dq 0x56407d199c079a9e
    dq 0x834f301ff8c7e70e
    dq 0x2c714cdc6049f63b
    dq 0x9639875abee7a228
    dq 0x6ebea47996265a9e
    dq 0x4744a730cda3c083
    dq 0xdc20c699c982ad9d
    dq 0xd1dae6dfa0ee3fa6
    dq 0x5531c0a14228856e
    dq 0xa2e2b6da2d52ef29
    dq 0xf0dc4a93faf38c70
    dq 0x958e02b843b0fc5a
    dq 0x5169d4b4ed0a3331
    dq 0x14acf94a73341023
    dq 0x2e19c384c2ff03da
    dq 0x36af811982038975
    dq 0xbc28aa4cb8194a3f
    dq 0x14b3e2ebed804ebe
    dq 0x5a410df9a68fcd46
    dq 0xa489f00152bdfd6e
    dq 0xa44fa781a36b38c6
    dq 0x2c9f1843cfa9d275
    dq 0xf08fbcc066acc937
    dq 0x6c56fee5b4bb4807
    dq 0xf7cb26533d58735b
    dq 0x3e60de1840d9981b
    dq 0xad8cc492dc0653af
    dq 0xdcaadd3846388fbc
    dq 0xab9b5277eca196c2
    dq 0xe66e33ce6c182b4f
    dq 0x045e4b27225e56a5
    dq 0xcb6c0371ed12b2e2
    dq 0xa7c8a45fdbc7ef09
    dq 0xfbca2ea00537c380
    dq 0x42f7567397da3d85
    dq 0x24d2333aec71a1c9
    dq 0xfc4d238075524339
    dq 0x2c5ccdcd76dd9151
    dq 0x9e2df766ad5cafe1
    dq 0x830f8906fc9becbd
    dq 0x4723c1099120b288
    dq 0x8442765b11abf9a1
    dq 0xe995ad7b5e4be56d
    dq 0x5eee043404c930d4
    dq 0x0b1d9c0e49cc8118
    dq 0x3b5257feec3d716d
    dq 0xb5dc885dbd8cea9f
    dq 0x59a2543e19d1c76b
    dq 0xf85d3f56e34e15e5
    dq 0xb458e5818470cd45
    dq 0x9a553ac58db3d8c0
    dq 0x73bfdf986118b91e
    dq 0xa5140dd46f25b785
    dq 0x3e0985032ef4d837
    dq 0xd6ac7960cc8db4b2
    dq 0x115cfaf775559090
    dq 0x577d6c081d6ea23a
    dq 0x38f767dc812ad5e1
    dq 0x0e6d2002bea86b4a
    dq 0x59f7495ea868672f
    dq 0xb01b11eafeedb9a7
    dq 0xf93afc29da444dbc
    dq 0x71b7126687d5ca0a
    dq 0xed8cbb46cbf5b8d9
    dq 0xe410dfe08eda987d
    dq 0xc06b22c8401a9050
    dq 0x1e0428f5c304a478
    dq 0x3dc6cd78c7f94ea2
    dq 0x2f365d86ef887e98
    dq 0x2125584bfafcd64c
    dq 0x8033a7cb7b05df07
    dq 0xa6ae030f3c104d79
    dq 0xf2fb9decda6ea4ca
    dq 0x48c4e2bf4dd0f598
    dq 0x08eb23deef0782e3
    dq 0xb8adb3b50946b811
    dq 0x2cbfaf5f47e0450e
    dq 0xc8b08413d11b2290
    dq 0x892adb75bf003f57
    dq 0x21dc0db7df2d4248
    dq 0x4f866487e4fc3eae
    dq 0xce942f380d39e25a
    dq 0xccf90ac00df3e754
    dq 0x38f5ee0e4982e7cc
    dq 0xf052431a8de950da
    dq 0x980c1e32c92a4852
    dq 0xc7997262f45013bb
    dq 0x9ad15ead207356a9
    dq 0x1301a83c89099f8f
    dq 0xccde9aabd8c00046
    dq 0xc232b09f70b51eeb
    dq 0xb90794507bb14766
    dq 0xde462e20e4ff6353
    dq 0xad42b987c568a226
    dq 0x3306550bc9904967
    dq 0xb45b4299f3f46545
    dq 0x915027f96237a96e
    dq 0xf8b9468f2d940db5
    dq 0xb7b76a77396c68f7
    dq 0x649fac07502a53a3
    dq 0xdf6825eb79313a09
    dq 0xfe4cf24b9aa5176a
    dq 0x312fc43df99e229e
    dq 0x6a35c371c2e8c168
    dq 0xdb83bda89ce33084
    dq 0x0743082a33a58a99
    dq 0x8718f93ed5d0bb53
    dq 0x405305be09af984c
    dq 0x278afe4c4fed737e
    dq 0x39ba30024d109d88
    dq 0x9a7ea315b4e356ff
    dq 0xbbc995c996b38f22
    dq 0xa0db3020e8da8226
    dq 0x5be7d9f5b138c510
    dq 0xd2bfdcb3c4d70e63
    dq 0xb525a2acb00d8297
    dq 0x7607db9e35994e0e
    dq 0xe457b51662da0a66
    dq 0xfce354b556caea92
    dq 0xad949f522fb3e278
    dq 0x913b3f4acf796178
    dq 0xfc4bf2a1ede4da4c
    dq 0xce321c4b2c909bdc
    dq 0xfbe82c17504e055e
    dq 0x8f516109a467c3c0
    dq 0xb1abea7aa6e0fa0e
    dq 0xde9ebc351687efd9
    dq 0xf2f4629255eabd3c
    dq 0x03928c8df19643c6
    dq 0x974527f3e6734584
    dq 0x730e38a33d63c54e
    dq 0x9b58549675045d80
    dq 0x27a808fdd10c777e
    dq 0x98d2d1e9af4c6444
    dq 0x8391809fccead473
    dq 0x36cc24c12025b235
    dq 0x4629fc371cfac5c1
    dq 0x7be7393732313ca8
    dq 0x12c5e108c5b28479
    dq 0x8d437b170eb0066a
    dq 0xf00b78e7e340f24b
    dq 0xdacc9b0e7c201b88
    dq 0x5a071d05c868db42
    dq 0x60c8a399ee7eee0e
    dq 0x00eeaee35974a3d3
    dq 0x2f5150e39fe2a8e7
    dq 0x9df7fcf5ec90ceb9
    dq 0x1ac10b1df66415b3
    dq 0x68c716dae87a205c
    dq 0xff74fe12f62c3fc4
    dq 0xd7f7db2c7b818b82
    dq 0x834e8fd8e3f1a181
    dq 0xafd8610b8a5ed89f
    dq 0x6906d3076e5d5266
    dq 0x6337dd8969faf367
    dq 0x0617fc64aac4b932
    dq 0x80b2c33103ab1d61
    dq 0x3432926b7b3ca587
    dq 0x3302d0234036c158
    dq 0x6d593762323c941c
    dq 0x7f4c2e0a599e4731
    dq 0x8ad66d3fd9d08dd2
    dq 0xfab250b0c0ad3c70
    dq 0xa67414526d0bbeaa
    dq 0xa57f45d5cd9c32c7
    dq 0x3edc8bdc76b951d3
    dq 0x45ab4e89bdf464d1
    dq 0x526df3bc0f326b81
    dq 0x728931bd401316dc
    dq 0xa3289ff2fee04bb7
    dq 0x059a49dd71860511
    dq 0x9f3d658f2813e878
    dq 0x2e470e9bb7ad26d4
    dq 0x1accaf8d1ee8be85
    dq 0xd5980407ca04d0de
    dq 0xa93a3115a80485bd
    dq 0xfd062caeff0e57be
    dq 0xcc580d40c9b27a84
    dq 0x96e75e9b246a5a81
    dq 0x039fb0b9795062b0
    dq 0x186aa343f1271454
    dq 0x48a0eb1704e299d5
    dq 0xc7d96f9e3387e230
    dq 0x21aa8b12da1ea40f
    dq 0xb7b75a788b67c4db
    dq 0xe760cafef6d7c135
    dq 0x84926f777d4e3c5f
    dq 0xbadfb79c401a4e7e
    dq 0x886b027f3c0c06dd
    dq 0xd56fd9822b827153
    dq 0x99ba2d41ca0b66f9
    dq 0x84300f7f4cfbb215
    dq 0xa66943bc8f7b6f98
    dq 0x07b0406c4baa3b92
    dq 0xa79c964195f53fce
    dq 0x5ca69bbd37526212
    dq 0x19c28d062aae3380
    dq 0x44e7e820cc395a69
    dq 0xe9a9edb89d0233dd
    dq 0x90b9ad910fd4533a
    dq 0x7ab89c669339d0b6
    dq 0xcfc7cb97e438e695
    dq 0x61078824f3e92c8d
    dq 0x57b3ea73c32b2c51
    dq 0x186a4d183b3e26a8
    dq 0x8f7de1a5c7c98073
    dq 0x02de021a8823e389
    dq 0xfeb8b9915d789b02
    dq 0xde63e244b1832b0c
    dq 0xedfa87e296a26670
    dq 0xa690fd915364e8ef
    dq 0x9763ea9a3ae27ae1
    dq 0xd216afa7a9a4b967
    dq 0x78195230a8e726b6
    dq 0x9f476e50eaa78cd0
    dq 0x153ea5dc37bd17b7
    dq 0xa58934555ef40125
    dq 0x8014c3b73a298d50
    dq 0x362ed0f36adb7616
    dq 0x87bfe5b0a9757b36
    dq 0x732ba0f54d974774
    dq 0x1a6c396a6845dd64
    dq 0xc7473dde20062f32
    dq 0x6f64b34638cf8ac0
    dq 0xe50f5a2552fd86c3
    dq 0x074388b5cf5c6e42
    dq 0xb2d976dd8e68b1e1
    dq 0x08c22a1f993a6f59
    dq 0xf48231b98a02c21d
    dq 0xd4524ef5ad7dfa13
    dq 0x97edfcf147cd67f0
    dq 0xa2219fea6c9b4082
    dq 0xc912d641dc0b8e2c
    dq 0x7d0259647c2e2cff
    dq 0x4aeb55a0548685b3
    dq 0x153059fb372f189d
    dq 0xfb745282a908d105
    dq 0x758752f5cc83cee8
    dq 0xb8612b5b96b9a9c6
    dq 0x3b09055f4f3beee2
    dq 0x98874d6f663d9e58
    dq 0x1adc82c132426e35
    dq 0xceda0f7ce49b5bd6
    dq 0x734ab77c61594174
    dq 0xbf7b8a9e546ac9fd
    dq 0x4854c2f58edb53a2
    dq 0xbfa79fb66568812f
    dq 0xfff3068f5918a8c5
    dq 0xc1e5b674cca35272
    dq 0x424ba85ca11356cf
    dq 0xadfa89a2aa33ac74
    dq 0x8e843b6d14225752

section .text

global compute_hash, init_hash_history, record_hash, check_repetition

extern board, side, castle, enpassant
extern position_hash
extern hash_history, hash_count

; ============================================================
; compute_hash - vypocita Zobrist hash aktualnej pozicie
; Vystup: rax = 64-bitovy hash
; ============================================================
compute_hash:
    push rbx
    push rcx
    push rdx
    push rsi
    push r12
    push r13

    xor r12, r12          ; hash = 0

    ; figury na polickach
    xor rcx, rcx          ; index policka 0..63
.square_loop:
    lea rsi, [board]
    movzx rax, byte [rsi + rcx]
    test rax, rax
    jz .next_square
    mov rbx, rax
    and rbx, 0xF          ; piece byte (1..6, 9..14)
    shl rbx, 6
    add rbx, rcx          ; index do zobrist_keys
    lea rsi, [zobrist_keys]
    xor r12, qword [rsi + rbx*8]
.next_square:
    inc rcx
    cmp rcx, 64
    jl .square_loop

    ; strana na tahu
    lea rsi, [side]
    movzx rax, byte [rsi]
    test rax, rax
    jz .no_side
    lea rsi, [zobrist_keys + (16*64)*8]
    xor r12, qword [rsi]
.no_side:

    ; prava rosady
    lea rsi, [castle]
    movzx rax, byte [rsi]
    mov rcx, 4
    lea rsi, [zobrist_keys + (16*64 + 1)*8]
.castle_loop:
    mov rbx, rcx
    dec rbx
    bt rax, rbx
    jnc .castle_next
    xor r12, qword [rsi + rbx*8]
.castle_next:
    loop .castle_loop

    ; en passant stlpec
    lea rsi, [enpassant]
    movzx rax, byte [rsi]
    cmp rax, 255
    je .ep_done
    and rax, 7            ; file
    lea rsi, [zobrist_keys + (16*64 + 1 + 4)*8]
    xor r12, qword [rsi + rax*8]
.ep_done:

    mov rax, r12
    lea rsi, [position_hash]
    mov qword [rsi], r12

    pop r13
    pop r12
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================
; E10/F2: inkrementalny Zobrist delta — search make/unmake namiesto
; plneho compute_hash. XOR je samoinverzny: funkcie sa volaju v make
; aj unmake identicky (rovnake kluce, rovnaky vysledok).
; Pozor: v unmake su r8-r11 live -> clobbruje len rax/rcx/rdx/rsi/rdi.
; ============================================================

global hash_delta_pieces, hash_delta_state
extern moved_piece, captured_piece, promo_pieces

; ------------------------------------------------------------
; hash_xor_piece - XOR Zobrist kľúča figúrky do position_hash
; Vstup: ecx = piece bajt, esi = sq
; Clobbers: rax, rdx, rdi
; ------------------------------------------------------------
hash_xor_piece:
    ; Ochrana pred deep-search / zastaranými priechodmi tahu: nikdy nesmú
    ; indexovať za hranice Zobrist tabuľky. Neplatné pole alebo figúrka sa
    ; spracujú ako no-op namiesto pádu enginu.
    cmp esi, 63
    ja .invalid
    mov eax, ecx
    and eax, 0xF
    cmp eax, 15
    ja .invalid
    shl eax, 6
    add eax, esi
    lea rdi, [zobrist_keys]
    mov rdx, [rdi + rax*8]
    xor [position_hash], rdx
    ret
.invalid:
    ret

; ------------------------------------------------------------
; hash_delta_pieces - figurkova delta tahu
; Vstup: ax = 16-bitovy tah; moved_piece/captured_piece nastavene
;   (make: po apply_move; unmake: z undo zaznamu)
; XOR: out moved@from, in (promo?nova:moved)@to, out captured@cap_sq,
;      out rook@rfrom + in rook@rto (rosada)
; ------------------------------------------------------------
hash_delta_pieces:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8                   ; zarovnanie (5 pushov + ret = misaligned)
    movzx r12d, ax
    and r12d, 0x3F               ; from
    mov r13d, eax
    shr r13d, 6
    and r13d, 0x3F               ; to
    mov r14d, eax
    shr r14d, 12                 ; flags
    ; hybana figurka: out @from, in @to
    movzx r15d, byte [moved_piece]
    mov ebx, r15d
    cmp r14d, FLAG_PROMO_Q
    jb .np
    cmp r14d, FLAG_PROMO_N
    ja .np
    lea rcx, [promo_pieces]
    movzx ebx, byte [rcx + r14]
    movzx ecx, byte [moved_piece]
    and ecx, COLOR_MASK
    or ebx, ecx
.np:
    mov ecx, r15d
    mov esi, r12d
    call hash_xor_piece          ; out moved @ from
    mov ecx, ebx
    mov esi, r13d
    call hash_xor_piece          ; in (promo/norm) @ to
    ; brana figurka: out @cap_sq (cap_sq = to, pri EP to-+8)
    movzx ecx, byte [captured_piece]
    test ecx, ecx
    jz .castle
    mov esi, r13d
    cmp r14d, FLAG_ENPASSANT
    jne .cap_go
    movzx eax, byte [moved_piece]
    test eax, COLOR_MASK
    jnz .ep_b
    sub esi, 8
    jmp .cap_go
.ep_b:
    add esi, 8
.cap_go:
    call hash_xor_piece
.castle:
    cmp r14d, FLAG_CASTLE
    jne .done
    cmp r13d, 6
    je .rwk
    cmp r13d, 2
    je .rwq
    cmp r13d, 62
    je .rbk
    cmp r13d, 58
    je .rbq
    jmp .done
.rwk:
    mov esi, 7
    mov r12d, 5                  ; rto (r12=from uz nie je potrebne)
    jmp .rook
.rwq:
    mov esi, 0
    mov r12d, 3
    jmp .rook
.rbk:
    mov esi, 63
    mov r12d, 61
    jmp .rook
.rbq:
    mov esi, 56
    mov r12d, 59
.rook:
    movzx ecx, byte [moved_piece]
    and ecx, COLOR_MASK
    or ecx, ROOK
    call hash_xor_piece          ; out rook @ rfrom
    mov esi, r12d                ; r12 prezije (callee-saved), rdi nie
    call hash_xor_piece          ; in rook @ rto
.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ------------------------------------------------------------
; hash_delta_state - delta stavovych klucov (strana, rosada, EP)
; XOR klucov pre AKTUALNE hodnoty [side]/[castle]/[enpassant].
; Volat raz pred zmenou stavu a raz po nej (make aj unmake).
; Clobbers: rax, rcx, rdx, rdi
; ------------------------------------------------------------
hash_delta_state:
    ; strana na tahu (kluc len pre ciernu, ako v compute_hash)
    movzx eax, byte [side]
    test eax, eax
    jz .no_side
    lea rdi, [zobrist_keys + (16*64)*8]
    mov rdx, [rdi]
    xor [position_hash], rdx
.no_side:
    ; prava rosady (bity 0..3)
    movzx eax, byte [castle]
    lea rdi, [zobrist_keys + (16*64 + 1)*8]
    xor ecx, ecx
.castle_loop:
    cmp ecx, 4
    jae .castle_done
    bt eax, ecx
    jnc .castle_next
    mov rdx, [rdi + rcx*8]
    xor [position_hash], rdx
.castle_next:
    inc ecx
    jmp .castle_loop
.castle_done:
    ; en passant stlpec
    movzx eax, byte [enpassant]
    cmp eax, 255
    je .ep_done
    and eax, 7
    lea rdi, [zobrist_keys + (16*64 + 1 + 4)*8]
    mov rdx, [rdi + rax*8]
    xor [position_hash], rdx
.ep_done:
    ret

; ============================================================
; init_hash_history - vynuluje historiu hashov
; ============================================================
init_hash_history:
    mov qword [hash_count], 0
    ret

; ============================================================
; record_hash - zapise aktualny position_hash do historie
; ============================================================
record_hash:
    push rax
    push rbx
    mov rbx, [hash_count]
    cmp rbx, HASH_HISTORY_MAX
    jge .done
    lea rax, [hash_history]
    mov rcx, [position_hash]
    mov [rax + rbx*8], rcx
    inc rbx
    mov [hash_count], rbx
.done:
    pop rbx
    pop rax
    ret

; ============================================================
; check_repetition - kontroluje 3-kratne opakovanie pozicie
; Vystup: rax = 1 ak 3x, inak 0
; Bounded scan: stacia posledne HASH_HISTORY_SCAN_MAX zaznamov historie,
; pri dlhych partiach netreba prehladavat celu historiu od zaciatku.
; ============================================================
check_repetition:
    push rbx
    push rcx
    push rdx

    mov rcx, [position_hash]
    xor rax, rax
    xor rdx, rdx
    xor rbx, rbx                ; start = 0
    cmp qword [hash_count], HASH_HISTORY_SCAN_MAX
    jbe .loop
    mov rbx, [hash_count]
    sub rbx, HASH_HISTORY_SCAN_MAX
.loop:
    cmp rbx, [hash_count]
    jge .done
    lea rsi, [hash_history]
    cmp [rsi + rbx*8], rcx
    jne .next
    inc rdx
    cmp rdx, 3
    jl .next
    mov rax, 1
    jmp .done
.next:
    inc rbx
    jmp .loop
.done:
    pop rdx
    pop rcx
    pop rbx
    ret