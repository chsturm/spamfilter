JsOsaDAS1.001.00bplist00�Vscriptof; ' u s e   s t r i c t ' ; 
 
 / / d e b u g g e r     / /   s t a r t   w e b   i n s p e c t o r   p a n e l 
 v a r   s h o u l d A l e r t M a t c h D e t a i l s   =   f a l s e ;     / /   t r u e :   a l e r t   r u l e   i t e m   i f   a   r u l e   m a t c h   i s   f o u n d 
 
 v a r   m a i l   =   A p p l i c a t i o n . c u r r e n t A p p l i c a t i o n ( ) ; 
 m a i l . i n c l u d e S t a n d a r d A d d i t i o n s   =   t r u e ; 
 O b j C . i m p o r t ( ' F o u n d a t i o n ' ) ; 
 
 / * *   l o a d   b l a c k l i s t   r u l e s   * / 
 v a r   p a t h   =   m a i l . p a t h T o ( " l i b r a r y   f o l d e r " ,   { f r o m :   " u s e r   d o m a i n " ,   f o l d e r C r e a t i o n :   f a l s e } ) . t o S t r i n g ( )   +   " / A p p l i c a t i o n   S c r i p t s / c o m . a p p l e . m a i l / s p a m f i l t e r - r u l e s . j s o n " 
 v a r   r u l e s L i s t   =   l o a d R u l e s ( p a t h ) 
 
 f u n c t i o n   l o a d R u l e s   ( p a t h )   { 
 	 t r y   { 
 	 	 v a r   f m   =   $ . N S F i l e M a n a g e r . d e f a u l t M a n a g e r 
 	 	 i f   ( ! f m . f i l e E x i s t s A t P a t h ( p a t h ) )   { 
 	 	 	 m a i l . d i s p l a y D i a l o g ( " N o   r u l e s   f i l e   f o u n d ! " ,   { w i t h I c o n :   " c a u t i o n " ,   g i v i n g U p A f t e r :   1 0 } ) 
 	 	 } 
 	 	 v a r   c o n t e n t s   =   f m . c o n t e n t s A t P a t h ( p a t h )   / /   N S D a t a 
 	 	 c o n t e n t s   =   $ . N S S t r i n g . a l l o c . i n i t W i t h D a t a E n c o d i n g ( c o n t e n t s ,   $ . N S U T F 8 S t r i n g E n c o d i n g ) ; 
 	 	 v a r   c o n f i g J s o n S t r   =   O b j C . u n w r a p ( c o n t e n t s ) 
 	 
 	 	 i f   ( c o n f i g J s o n S t r   ! =   " " ) 
 	 	 	 v a r   c o n f i g   =   J S O N . p a r s e ( c o n f i g J s o n S t r ) 
 	 	 e l s e 
 	 	 	 c o n s o l e . l o g ( " N o   r u l e s   f o u n d ! " ) 
 	 }   c a t c h   ( e )   { 
 	 	 c o n s o l e . l o g ( e . n a m e   + ' :   ' +   e . m e s s a g e ) 
 	 } 
 	 
 	 i f   ( ! c o n f i g   | |   ! c o n f i g . r u l e s L i s t )   r e t u r n   [ ] 
 	 i f   ( c o n f i g . s h o u l d A l e r t M a t c h D e t a i l s   = = =   t r u e   | |   c o n f i g . s h o u l d A l e r t M a t c h D e t a i l s   ! = =   " f a l s e " ) 
 	 	 s h o u l d A l e r t M a t c h D e t a i l s   =   c o n f i g . s h o u l d A l e r t M a t c h D e t a i l s 
 	 r e t u r n   c o n f i g . r u l e s L i s t 
 } 
 
 
 / * *   T h e s e   c h a r s   a r e   u s u a l l y   n o t   u s e d   w i t h i n   n o r m a l   t e x t , 
 	 b u t   t o   p r e v e n t   w o r d - b a s e d   b l a c k l i s t i n g   i n   s p a m . 
 	 e . g .   z e r o - w i d t h   s p a c e s   l i k e   b y t e   o r d e r   m a r k 
 * / 
 v a r   c h e a t C h a r s   =   [ ' \ u F E F F ' , ' \ u 2 0 0 B ' ,   ' \ u 2 0 6 0 ' ] ; 
 
 / * *   u n c o m m o n   f i l e   e x t e n s i o n s   * / 
 v a r   f i l e E x t e n s i o n s   =   [ ' . 7 z ' ,   ' . e x e ' ,   ' . j p g . z i p ' ] ; 
 
 / * *   u n c o m m o n   c h a r s e t s   ( i n   l o w e r c a s e )   * / 
 v a r   c h a r s e t B l a c k l i s t   =   [ ' w i n d o w s - 1 2 5 1 ' / *   c y r i l l i c * / ,   ' g b 2 3 1 2 ' / * c h i n e s e * / ,   ' g b 1 8 0 3 0 ' / * c h i n e s e * / ] ; 
 
 / * *   h a n d l e r   c a l l e d   b y   A p p l e   M a i l   w h e n   a p p l y i n g   r u l e s   o n   m e s s a g e s   * / 
 f u n c t i o n   p e r f o r m M a i l A c t i o n W i t h M e s s a g e s   ( m e s s a g e s )   { 
 	 m a i l . d o w n l o a d H t m l A t t a c h m e n t s   =   f a l s e ; 
 
 	 m e s s a g e s . f o r E a c h ( f u n c t i o n ( m e s s a g e )   { 
 	 	 / /   s e a r c h   m a t c h i n g   r u l e   b a s e d   o n   e m a i l   a d d r e s s 
 	 	 v a r   r u l e   =   r u l e s L i s t . f i n d ( f u n c t i o n ( r u l e )   { 
 	 	 	 v a r   a c c o u n t   =   m e s s a g e . m a i l b o x ( ) . a c c o u n t ( ) ; 
 	 	 	 r e t u r n   a c c o u n t . e m a i l A d d r e s s e s ( ) . s o m e ( f u n c t i o n ( a d d r e s s ) { 
 	 	 	 	 r e t u r n   a d d r e s s   = = =   r u l e . e m a i l ; 
 	 	 	 } ) ; 
 	 	 } ) ; 
 	 
 	 	 i f   ( r u l e )   { 
 	 	 	 / /   d e l e t e   m e s s a g e   a s   s o o n   a s   a   b l a c k l i s t   m a t c h   i s   d e t e c t e d 
 	 	 	 i f   ( t e s t S e l f A d d r e s s e d F o r F u l l N a m e ( r u l e . e m a i l ,   m e s s a g e ) 
 	 	 	 	   | |   t e s t S e n d e r F o r F u l l N a m e ( r u l e . f r o m W h i t e l i s t ,   m e s s a g e ) 
 	 	 	 	   | |   t e s t M e s s a g e F i e l d ( ' s e n d e r ' ,   r u l e . s e n d e r B l a c k l i s t ,   m e s s a g e ) 
 	 	 	 	   | |   t e s t M e s s a g e F i e l d ( ' s u b j e c t ' ,   r u l e . s u b j e c t B l a c k l i s t ,   m e s s a g e ) 
 	 	 	 	   | |   t e s t M e s s a g e F i e l d ( ' s o u r c e ' ,   r u l e . c o n t e n t B l a c k l i s t ,   m e s s a g e ) )   { 
 	 	 	 	 / /   m a r k   m e s s a g e   a s   p r o c e s s e d   b y   s p a m f i l t e r   f o r   d e b u g g i n g 
 	 	 	 	 / * m e s s a g e . f l a g I n d e x   =   6 ; 	 / /   g r e y 
 	 	 	 	 m e s s a g e . f l a g g e d S t a t u s   =   t r u e ; * / 
 	 	 	 	 
 	 	 	 	 m o v e T o T r a s h ( m e s s a g e ) ; 
 	 	 	 	 d e l a y ( 0 . 5 ) ; 
 	 	 	 } 
 	 	 	 e l s e 
 	 	 	 	 c o n s o l e . l o g ( " N o   b l a c k l i s t   m a t c h e s   f o u n d " ) ; 
 	 	 } 
 	 } ) ; 
 } ; 
 
 / * *   A l e r t   i t e m   t h a t   m a t c h e d   a   r u l e ;   u s e f u l   f o r   e n h a n c i n g   r u l e s   * / 
 f u n c t i o n   a l e r t M a t c h D e t a i l s   ( f i e l d ,   i t e m )   { 
 	 i f   ( ! s h o u l d A l e r t M a t c h D e t a i l s )   r e t u r n ; 
 	 m a i l . d i s p l a y D i a l o g ( f i e l d   + ' :   ' +   i t e m ,   { w i t h T i t l e :   ' S p a m f i l t e r   m a t c h   d e t a i l s ' } ) ; 
 } 
 
 / * *   r e t u r n s   s p a m   m a t c h   ( t r u e )   i f   s e l f   a d d r e s s e d   e m a i l   ( s e n d e r   = = =   r e c e i v e r   a d d r e s s )   d o e s n ' t   i n c l u d e   a c c o u n t   o w n e r ' s   f u l l   n a m e   * / 
 f u n c t i o n   t e s t S e l f A d d r e s s e d F o r F u l l N a m e   ( a c c o u n t E m a i l ,   m e s s a g e )   { 
 	 v a r   f r o m   =   m e s s a g e . s e n d e r ( ) 
 	 i f   ( f r o m   = =   " " )   r e t u r n   t r u e     / /   n o   s e n d e r   p r o v i d e d 
 	 i f   ( f r o m . i n c l u d e s ( a c c o u n t E m a i l ) )   { 
 	 	 c o n s t   r e s   =   ! f r o m . i n c l u d e s ( m e s s a g e . m a i l b o x ( ) . a c c o u n t ( ) . f u l l N a m e ( ) ) 
 	 	 i f   ( r e s )   a l e r t M a t c h D e t a i l s ( ' S e n d e r   = =   r e c e i v e r   t e s t ' ,   ' S e l f   a d d r e s s e d   w i t h o u t   f u l l   n a m e ' ) 
 	 	 r e t u r n   r e s 
 	 } 
 	 r e t u r n   f a l s e 
 } 
 
 / * *   r e t u r n s   s p a m   m a t c h   ( t r u e )   i f   s e n d e r ' s   n a m e   c o n s i s t s   o f   o n l y   o n e   w o r d   n o t   i n c l u d e d   i n   w h i t e l i s t   a n d   w h i t e l i s t . s h o u l d T e s t   = =   t r u e   * / 
 f u n c t i o n   t e s t S e n d e r F o r F u l l N a m e   ( w h i t e l i s t ,   m e s s a g e )   { 
 	 i f   ( ! w h i t e l i s t . s h o u l d T e s t )   r e t u r n   f a l s e 
 	 c o n s t   f r o m   =   m e s s a g e . s e n d e r ( ) 
 	 c o n s t   a d d r e s s I d x   =   f r o m . i n d e x O f ( " < " )     / /   e . g .   X   Y   < x y @ a b c . c o m > 
 	 i f   ( a d d r e s s I d x   < =   0 )   r e t u r n   f a l s e 
 	 c o n s t   n a m e   =   f r o m . s u b s t r i n g ( 0 ,   a d d r e s s I d x ) . t r i m ( ) 
 	 i f   ( n a m e . i n d e x O f ( "   " )   >   0 )   r e t u r n   f a l s e 
 	 c o n s t   r e s   =   ! w h i t e l i s t . l i s t . i n c l u d e s ( n a m e ) 
 	 i f   ( r e s )   a l e r t M a t c h D e t a i l s ( ' S e n d e r   w i t h   f u l l   n a m e   t e s t ' ,   ' F o u n d   o n l y   o n e   w o r d ' ) 
 	 r e t u r n   r e s 
 } 
 
 / * *   t e s t s   f o r   m a t c h e s   b e t w e e n   m e s s a g e   f i e l d   a n d   b l a c k l i s t   * / 
 f u n c t i o n   t e s t M e s s a g e F i e l d   ( f i e l d ,   b l a c k l i s t ,   m e s s a g e )   { 
 	 v a r   s e a r c h C o n t e n t   =   m e s s a g e [ f i e l d ] ( ) ; 
 	 
 	 i f   ( f i e l d   = = =   " s o u r c e " )   { 
 	 	 / /   d e t e r m i n e   b o u n d a r y   f o r   m u l t i p a r t   m e s s a g e s 
 	 	 v a r   h e a d e r s   =   m e s s a g e . a l l H e a d e r s ( ) 
 	 	 v a r   b o u n d a r y   =   ' ' 
 	 }   e l s e   / /   i . e .   s e n d e r ,   s u b j e c t 
 	 	 r e t u r n   b l a c k l i s t . l i s t . s o m e ( f u n c t i o n ( i t e m )   { 
 	 	 	 i f   ( i t e m . l e n g t h   = = =   0 ) 
 	 	 	 	 r e t u r n   f a l s e   / /   a v o i d   e m p t y   s t r i n g s   c r e a t e d   b y   a c c i d e n t 
 	 	 	 c o n s t   r e s   =   s e a r c h C o n t e n t . i n c l u d e s ( i t e m ) ;     / /   t r u e   i f   m a t c h   i n   b l a c k l i s t 
 	 	 	 i f   ( r e s )   a l e r t M a t c h D e t a i l s ( ' F i e l d   " ' +   f i e l d   + ' " ' ,   i t e m ) 
 	 	 	 r e t u r n   r e s 
 	 	 } ) 
 
 	 / /   s e a r c h   m e s s a g e   b o d y   f r o m   r a w   s o u r c e 
 	 v a r   i n i t S e a r c h P o s   =   0 
 	 v a r   m e s s a g e C o m p o n e n t s H a n d l e r   =   n e w   M e s s a g e C o m p o n e n t s H a n d l e r ( s e a r c h C o n t e n t ,   i n i t S e a r c h P o s ,   b o u n d a r y ) 
 	 w h i l e   ( m e s s a g e C o m p o n e n t s H a n d l e r . h a s N e x t P a r t ( ) )   { 
 	 	 / /   s e a r c h   f o r   b l a c k l i s t   i t e m   w i t h i n   c u r r e n t   m e s s a g e   p a r t 
 	 	 v a r   p a r t   =   m e s s a g e C o m p o n e n t s H a n d l e r . g e t N e x t P a r t ( ) ; 
 	 	 i f   ( p a r t   = = =   f a l s e ) 
 	 	 	 / /   m e s s a g e   n o t   s e a r c h a b l e 
 	 	 	 r e t u r n   f a l s e ; 
 	 	 
 	 	 / /   c h e c k   f o r   e v i l   f i l e   n a m e   o r   f i l e   e x t e n s i o n s 
 	 	 i f   ( p a r t . f i l e N a m e   ! = =   n u l l )   { 
 	 	 	 i f   ( f i l e E x t e n s i o n s . s o m e ( f u n c t i o n ( c )   { 
 	 	 	 	     c o n s t   r e s   =   p a r t . f i l e N a m e . i n d e x O f ( c )   > =   0 
 	 	 	 	     i f   ( r e s )   a l e r t M a t c h D e t a i l s ( ' F i l e   e x t e n s i o n ' ,   c ) 
 	 	 	 	     r e t u r n   r e s 
 	 	 	 	 } ) 
 	 	 	 ) 
 	 	 	 	 r e t u r n   t r u e 
 	 	 	 c o n t i n u e 
 	 	 } 
 	 	 / /   c h e c k   f o r   e v i l   c h a r s e t s 
 	 	 i f   ( p a r t . t y p e   ! = =   n u l l )   { 
 	 	 	 i f   ( c h a r s e t B l a c k l i s t . s o m e ( f u n c t i o n ( c )   { 
 	 	 	 	     c o n s t   r e s   =   p a r t . t y p e . i n d e x O f ( c )   > =   0 
 	 	 	 	     i f   ( r e s )   a l e r t M a t c h D e t a i l s ( ' C h a r s e t ' ,   c ) 
 	 	 	 	     r e t u r n   r e s 
 	 	 	 	 } ) 
 	 	 	 ) 
 	 	 	 	 r e t u r n   t r u e 
 	 	 } 
 	 	 
 	 	 v a r   s e a r c h T a r g e t   =   s e a r c h C o n t e n t 
 	 	 v a r   s e a r c h P a r t S t a r t   =   p a r t . s t a r t 
 	 	 i f   ( p a r t . e n c o d i n g   = = =   " b a s e 6 4 "   | |   p a r t . t y p e . i n d e x O f ( " h t m l " )   > =   0 
 	 	     | |   p a r t . e n c o d i n g   = = =   " q u o t e d - p r i n t a b l e " )   { 
 	 	 	 / /   c h o o s e   d e c o d e d   s t r i n g   a s   s e a r c h   t a r g e t 
 	 	 	 v a r   d e c o d e d C o n t e n t   =   p a r t . d e c o d e ( s e a r c h T a r g e t ) 
 	 	 	 i f   ( t y p e o f   d e c o d e d C o n t e n t   ! = =   " u n d e f i n e d " )   { 
 	 	 	 	 s e a r c h T a r g e t   =   d e c o d e d C o n t e n t 
 	 	 	 	 s e a r c h P a r t S t a r t   =   0     / /   d e c o d e d   t e x t   i s   u n r e l a t e d   t o   p a r t   p o s i t i o n i n g   o f   o r i g i n a l   m e s s a g e ! 
 	 	 	 } 
 	 	 } 
 	 	 
 	 	 v a r   s e a r c h P a r t   =   s e a r c h T a r g e t . s u b s t r i n g ( s e a r c h P a r t S t a r t ,   p a r t . e n d ) 
 	 	 
 	 	 / /   c h e c k   f o r   c h e a t i n g   z e r o - w i d t h   s p a c e s   o n c e   p e r   m e s s a g e   p a r t 
 	 	 i f   ( m e s s a g e C o m p o n e n t s H a n d l e r . i s P a r s e d   = = =   f a l s e   & &   c h e a t C h a r s . s o m e ( f u n c t i o n ( c )   { 
 	 	 	 	 c o n s t   r e s   =   s e a r c h P a r t . i n d e x O f ( c ,   1 )   >   0 
 	 	 	 	 i f   ( r e s )   { 
 	 	 	 	 	 c o n s t   u n i c o d e   =   ' U + ' +   c . c o d e P o i n t A t ( 0 ) . t o S t r i n g ( 1 6 ) . t o U p p e r C a s e ( ) 
 	 	 	 	 	 a l e r t M a t c h D e t a i l s ( ' C h e a t   c h a r ' ,   u n i c o d e ) 
 	 	 	 	 } 
 	 	 	 	 r e t u r n   r e s 
 	 	 	 } ) 
 	 	 ) 
 	 	 	 r e t u r n   t r u e     / /   c h e a t   c h a r   d e t e c t e d   = >   s p a m   m a i l 
 	 	 	     
 	 	 i f   ( b l a c k l i s t . l i s t . s o m e ( f u n c t i o n ( i t e m )   { 
 	 	 	 	 c o n s t   r e s   =   s e a r c h P a r t . i n d e x O f ( i t e m )   ! = =   - 1   & &   i t e m . l e n g t h   >   0 
 	 	 	 	 i f   ( r e s )   a l e r t M a t c h D e t a i l s ( ' T e x t   c o n t e n t ' ,   i t e m ) 
 	 	 	 	 r e t u r n   r e s 
 	 	 	 } ) 
 	 	 ) 
 	 	 	 r e t u r n   t r u e     / /   m a t c h   i n   b l a c k l i s t 
 	 } 
 	 r e t u r n   f a l s e     / /   n o   m a t c h e s   i n   b l a c k l i s t 
 } 
 
 / * *   m o v e s   s p e c i f i e d   m e s s a g e   t o   t r a s h   f o l d e r   o f   i t s   m a i l   a c c o u n t   * / 
 f u n c t i o n   m o v e T o T r a s h   ( m e s )   { 
 	 m e s . j u n k M a i l S t a t u s   =   t r u e 
 	 / / m e s . d e l e t e d S t a t u s   =   t r u e   / /   m e s s a g e   l o s t   i n   t h e   N i r w a n a 
 	 v a r   a c c o u n t   =   m e s . m a i l b o x ( ) . a c c o u n t ( ) 
 	 i f   ( ! a c c o u n t )   m a i l . d i s p l a y D i a l o g ( " A c c o u n t   o f   m a i l b o x   u n d e f i n e d " ) 
 	 
 	 / /   g e t   t r a s h   m a i l b o x   o f   a c c o u n t 
 	 v a r   b o x L i s t   =   a c c o u n t . m a i l b o x e s ( ) 
 	 i f   ( ! b o x L i s t   | |   b o x L i s t . l e n g t h   = = =   0 )   m a i l . d i s p l a y D i a l o g ( " M a i l b o x   l i s t   u n d e f i n e d " ) 
 	 
 	 v a r   t r a s h   =   b o x L i s t . f i n d ( f u n c t i o n ( b o x ) { 
 	 	 v a r   b o x N a m e   =   b o x . n a m e ( ) 
 	 	 v a r   e x i s t s   =   b o x N a m e . i n c l u d e s ( " D e l e t e d   M e s s a g e s " ) 
 	 	 r e t u r n   e x i s t s   | |   b o x N a m e . i n c l u d e s ( " T r a s h " ) 
 	 } ) ; 
 	 i f   ( ! t r a s h )   { 
 	 	 m a i l . d i s p l a y D i a l o g ( " T r a s h   u n d e f i n e d   f o r   a c c o u n t   "   +   a c c o u n t . n a m e ( ) ) 
 	 	 r e t u r n 
 	 } 
 
 	 m e s . m a i l b o x   =   t r a s h ( ) 
 	 m a i l . c h e c k F o r N e w M a i l ( a c c o u n t ) 
 } 
 
 
 / /   h e l p e r   f u n c t i o n s 
 / * *   i n c l u d e s   a l l   p r o p e r t i e s   a n d   a c t i o n s   r e q u i r e d   f o r   m e s s a g e   p a r t   h a n d l i n g   * / 
 f u n c t i o n   M e s s a g e P a r t   ( s t a r t ,   e n d ,   t y p e ,   e n c o d i n g )   { 
 	 t h i s . s t a r t   =   s t a r t 	 	 	 / /   s t a r t   p o s i t i o n   o f   m e s s a g e   p a r t   c o n t e n t 
 	 t h i s . e n d   =   e n d 	 	 	 	 / /   e n d   p o s i t i o n   o f   m e s s a g e   p a r t   c o n t e n t 
 	 t h i s . t y p e   =   t y p e . t o L o w e r C a s e ( )   / /   c o n t e n t - t y p e   o f   m e s s a g e   p a r t 
 	 t h i s . f i l e N a m e   =   n u l l 	 	 / /   s e t   i f   p a r t   c o n t a i n s   a   b i n a r y   f i l e 
 	 t h i s . e n c o d i n g   =   e n c o d i n g . t o L o w e r C a s e ( )   / /   c o n t e n t - t r a n s f e r - e n c o d i n g   o f   m e s s a g e   p a r t 
 	 t h i s . m u l t i B o u n d a r y   =   ' ' 	 / /   b o u n d a r y   a t   t h e   v e r y   e n d   o f   t h e   p a r t   ( m u l t i p a r t / . . . ) 
 	 t h i s . d e c o d e d   =   n u l l 	 	 / /   d e c o d e d   m e s s a g e   p a r t   c o n t e n t   i f   r a w   d a t a   i s   b 6 4   e n c o d e d   o r   h t m l   e n t i t i e s   m i g h t   b e   i n c l u d e d 
 	 
 	 / * *   s e t s   e n d   p o s i t i o n   o f   m e s s a g e   p a r t   o n l y   i f   n o t   a l r e a d y   s e t   * / 
 	 t h i s . s e t E n d   =   f u n c t i o n ( e ) { i f   ( t h i s . e n d   = = =   0 )   t h i s . e n d   =   e } 
 	 
 	 / * *   t r u e ,   w h e n   e n d   p o s i t i o n   i s   s e t   * / 
 	 t h i s . h a s E n d   =   f u n c t i o n ( ) { r e t u r n   t h i s . e n d   ! = =   0 } 
 	 
 	 / * *   s e t s   a n d   r e t u r n s   d e c o d e d   m e s s a g e   p a r t   c o n t e n t   i f   r a w   d a t a   i s   b 6 4 / q p   e n c o d e d ;   n o r m a l i z e   u m l a u t s   a n d   d e c o d e   & # d d d ;   c h a r s   i n   h t m l * / 
 	 t h i s . d e c o d e   =   f u n c t i o n ( r a w M s g ) { 
 	 	 i f   ( t h i s . d e c o d e d   ! = =   n u l l )   r e t u r n   t h i s . d e c o d e d 
 	 	 	 
 	 	 / /   e x t r a c t   c h a r s e t   f r o m   c o n t e n t - t y p e 
 	 	 v a r   c h a r s e t   =   " " ,   c h a r s e t I d x   =   t h i s . t y p e . i n d e x O f ( " c h a r s e t = " ) 
 	 	 i f   ( c h a r s e t I d x   >   0 )   { 
 	 	 	 c h a r s e t   =   t h i s . t y p e . s u b s t r ( c h a r s e t I d x + 8 ) . t r i m ( ) 
 	 	 	 i f   ( c h a r s e t [ 0 ]   = = =   ' " ' )     / /   o m i t   l e a d i n g /   t r a i l i n g   q u o t e   m a r k s 
 	 	 	 	 c h a r s e t   =   c h a r s e t . s u b s t r ( 1 ,   c h a r s e t . l e n g t h - 2 ) . t r i m ( ) 
 	 	 } 
 	 	 
 	 	 v a r   i n p u t S t r   =   r a w M s g . s u b s t r i n g ( t h i s . s t a r t ,   t h i s . e n d )     / /   e n c o d e d   m e s s a g e   p a r t 
 	 	 
 	 	 / /   h a n d l e   t r a n s f e r   e n c o d i n g 
 	 	 i f   ( t h i s . e n c o d i n g   = = =   " b a s e 6 4 " )   { 
 	 	 	 v a r   w s F r e e S t r   =   i n p u t S t r . r e p l a c e ( / \ s + / g ,   " " ) 
 	 	 	 i f   ( w s F r e e S t r . s t a r t s W i t h ( " 7 7 u / " ) )   / /   s k i p   b i n a r y   i n d i c a t o r   b e f o r e   d e c o d e 
 	 	 	 	 w s F r e e S t r   =   w s F r e e S t r . s u b s t r i n g ( 4 ) 
 	 	 	 t h i s . d e c o d e d   =   b 6 4 D e c o d e U n i c o d e ( w s F r e e S t r ,   c h a r s e t ) 
 	 	 } 
 	 	 e l s e   i f   ( t h i s . e n c o d i n g   = = =   " q u o t e d - p r i n t a b l e " )   { 
 	 	 	 t h i s . d e c o d e d   =   q p D e c o d e U n i c o d e ( i n p u t S t r ,   c h a r s e t ) 
 	 	 } 
 	 	 
 	 	 i f   ( t h i s . t y p e . i n d e x O f ( " h t m l " )   > =   0 )   { 
 	 	 	 i f   ( t h i s . d e c o d e d   = =   n u l l )   t h i s . d e c o d e d   =   i n p u t S t r 
 	 	 	 t h i s . d e c o d e d   =   h t m l D e c o d e U n i c o d e ( t h i s . d e c o d e d ) 
 	 	 } 
 	 	 r e t u r n   t h i s . d e c o d e d 
 	 } 
 } 
 
 / * *   r e t u r n s   c o n t e n t   o f   n e x t   s p e c i f i e d   h e a d e r   a s   w e l l   a s   s t a r t   a n d   e n d   p o s i t i o n   o f   t h e   h e a d e r   l i n e   r e l a t i v e   t o   s e a r c h C o n t e n t   * / 
 f u n c t i o n   g e t L o c a l H e a d e r   ( h e a d e r N a m e ,   s e a r c h C o n t e n t ,   s t a r t P o s )   { 
 	 h e a d e r N a m e   =   " \ n "   +   h e a d e r N a m e   +   " : "     / /   e . g .   " \ n C o n t e n t - T y p e : " 
 	 v a r   h e a d e r S t a r t P o s   =   s e a r c h C o n t e n t . i n d e x O f ( h e a d e r N a m e ,   s t a r t P o s ) 
 	 i f   ( h e a d e r S t a r t P o s + +   = = =   - 1 )   {     / /   s k i p   l e a d i n g   \ n   b y   + + 
 	 	 / /   h e a d e r   n a m e   n o t   f o u n d   = >   t r y   a g a i n   w i t h   l o w e r - c a s e ,   e . g . ,   " \ n C o n t e n t - t y p e : " 
 	 	 h e a d e r N a m e   =   " \ n "   +   h e a d e r N a m e [ 1 ]   +   h e a d e r N a m e . s u b s t r i n g ( 2 ) . t o L o w e r C a s e ( ) ; 
 	 	 h e a d e r S t a r t P o s   =   s e a r c h C o n t e n t . i n d e x O f ( h e a d e r N a m e ,   s t a r t P o s ) 
 	 	 i f   ( h e a d e r S t a r t P o s + +   = = =   - 1 ) 
 	 	 	 r e t u r n   f a l s e     / /   h e a d e r   n o t   f o u n d 
 	 } 
 	 v a r   h e a d e r E n d P o s   =   s e a r c h C o n t e n t . i n d e x O f ( " \ n " ,   h e a d e r S t a r t P o s   +   h e a d e r N a m e . l e n g t h ) 
 	 v a r   l i n e   =   s e a r c h C o n t e n t . s u b s t r i n g ( h e a d e r S t a r t P o s   +   h e a d e r N a m e . l e n g t h ,   h e a d e r E n d P o s ) . t r i m ( ) 
 	 v a r   l i n e E n d P o s   =   h e a d e r E n d P o s 
 	 	 
 	 w h i l e   ( l i n e [ l i n e . l e n g t h - 1 ]   = = =   " ; " )   { 
 	 	 / /   a n o t h e r   p a r a m e t e r   i n   n e x t   l i n e 
 	 	 h e a d e r E n d P o s   =   s e a r c h C o n t e n t . i n d e x O f ( " \ n " ,   h e a d e r E n d P o s + 1 ) 
 	 	 l i n e   =   s e a r c h C o n t e n t . s u b s t r i n g ( l i n e E n d P o s + 1 ,   h e a d e r E n d P o s ) . t r i m ( ) 
 	 	 l i n e E n d P o s   =   h e a d e r E n d P o s 
 	 } 
 	 
 	 r e t u r n   { h e a d e r C o n t e n t :   s e a r c h C o n t e n t . s u b s t r i n g ( h e a d e r S t a r t P o s   +   h e a d e r N a m e . l e n g t h ,   h e a d e r E n d P o s ) . t r i m ( ) , 
 	 	 l i n e S t a r t P o s :   h e a d e r S t a r t P o s , 
 	 	 l i n e E n d P o s :   h e a d e r E n d P o s } 
 } 
 
 / * *   P a r s e s   m e s s a g e   b o d y   a n d   b u i l d s   l i s t   o f   m e s s a g e   p a r t s   * / 
 f u n c t i o n   M e s s a g e C o m p o n e n t s H a n d l e r   ( r a w M e s s a g e ,   c o n t e n t S t a r t P o s ,   b o u n d a r y )   { 
 	 t h i s . r a w M e s s a g e   =   r a w M e s s a g e 
 	 t h i s . c o n t e n t S t a r t P o s   =   c o n t e n t S t a r t P o s 
 	 t h i s . s e a r c h P o s   =   c o n t e n t S t a r t P o s 
 	 t h i s . b o u n d a r y   =   b o u n d a r y 
 	 t h i s . b o u n d a r y L i s t   =   b o u n d a r y   ?   [ b o u n d a r y ]   :   [ ] 
 	 t h i s . p a r t s L i s t   =   [ ] 
 	 t h i s . p a r t I d x   =   0     / /   I N T E R N A L   p a r t   i n d e x 
 	 t h i s . i s P a r s e d   =   f a l s e 
 	 
 	 t h i s . h a s N e x t P a r t   =   f u n c t i o n ( )   { 
 	 	 r e t u r n   ( t h i s . p a r t s L i s t . l e n g t h   >   t h i s . p a r t I d x )   | |   ! t h i s . i s P a r s e d 
 	 } ; 
 	 
 	 t h i s . r e s e t I t e r a t o r   =   f u n c t i o n ( )   { 
 	 	 t h i s . p a r t I d x   =   0 
 	 } ; 
 	 
 	 t h i s . g e t N e x t P a r t   =   f u n c t i o n ( )   { 
 	 	 i f   ( ! t h i s . h a s N e x t P a r t ( ) ) 
 	 	 	 / /   i n d e x   o u t   o f   b o u n d s 
 	 	 	 r e t u r n   f a l s e 
 
 	 	 i f   ( t h i s . i s P a r s e d   = = =   t r u e ) 
 	 	 	 / /   g e t   m e s s a g e   p a r t   s e t   d u r i n g   i t e r a t i o n   f o r   p r e v i o u s   s e a r c h   i t e m 
 	 	 	 r e t u r n   t h i s . p a r t s L i s t [ t h i s . p a r t I d x + + ] 
 
 	 	 / /   s e a r c h   f o r   f u r t h e r   c o n t e n t   h e a d e r s   a s   l o n g   a s   l i s t   o f   p a r t s   i s   i n c o m p l e t e 
 	 	 v a r   c o n t e n t T r a n s E n c o d i n g   =   g e t L o c a l H e a d e r ( " C o n t e n t - T r a n s f e r - E n c o d i n g " ,   t h i s . r a w M e s s a g e ,   t h i s . s e a r c h P o s ) 
 	 	 v a r   c o n t e n t T y p e   =   g e t L o c a l H e a d e r ( " C o n t e n t - T y p e " ,   t h i s . r a w M e s s a g e ,   t h i s . s e a r c h P o s ) 
 
 	 	 i f   ( ( c o n t e n t T r a n s E n c o d i n g   | |   c o n t e n t T y p e )   = =   f a l s e )   { 
 	 	 	 / /   n o   m o r e   r e l e v a n t   s e a r c h   c o n t e n t   l e f t 
 	 	 	 t h i s . i s P a r s e d   =   t r u e 
 	 	 	 t h i s . r e s e t I t e r a t o r ( ) 
 	 	 	 r e t u r n   f a l s e 
 	 	 } 
 	 	 
 	 	 / /   d e f i n e   n e w   a d d i t i o n a l   m e s s a g e   p a r t 
 	 	 i f   ( ! c o n t e n t T r a n s E n c o d i n g   | |   ! c o n t e n t T y p e )   { 
 	 	 	 v a r   b e y o n d H e a d e r s P o s   =   c o n t e n t T y p e . l i n e E n d P o s 
 	 	 	 v a r   d u m m y   =   { h e a d e r C o n t e n t :   " " ,   l i n e S t a r t P o s :   u n d e f i n e d ,   l i n e E n d P o s :   u n d e f i n e d } 
 	 	 	 i f   ( b e y o n d H e a d e r s P o s   = =   u n d e f i n e d )   { 
 	 	 	 	 c o n t e n t T y p e   =   d u m m y 
 	 	 	 	 b e y o n d H e a d e r s P o s   =   c o n t e n t T r a n s E n c o d i n g . l i n e E n d P o s 
 	 	 	 } 
 	 	 	 e l s e 
 	 	 	 	 c o n t e n t T r a n s E n c o d i n g   =   d u m m y 
 	 	 } 
 	 	 e l s e   { 
 	 	 	 v a r   m i n H e a d e r   =   M a t h . m i n ( c o n t e n t T y p e . l i n e E n d P o s ,   c o n t e n t T r a n s E n c o d i n g . l i n e E n d P o s ) 
 	 	 	 v a r   c o r r u p t e d H e a d e r   =   t h i s . r a w M e s s a g e . i n d e x O f ( " \ n \ n " ,   m i n H e a d e r ) 
 	 	 	 i f   ( c o n t e n t T y p e . l i n e E n d P o s   >   c o r r u p t e d H e a d e r   | |   c o n t e n t T r a n s E n c o d i n g . l i n e E n d P o s   >   c o r r u p t e d H e a d e r )   { 
 	 	 	 	 / /   o n e   o f   t h e   t w o   h e a d e r s   i s   m i s s i n g 
 	 	 	 	 v a r   b e y o n d H e a d e r s P o s   =   c o n t e n t T y p e . l i n e E n d P o s 
 	 	 	 	 c o n t e n t T r a n s E n c o d i n g . h e a d e r C o n t e n t   =   " "     / /   h e a d e r   f o r   w r o n g   p a r t 
 	 	 	 } 
 	 	 	 e l s e 
 	 	 	 	 v a r   b e y o n d H e a d e r s P o s   =   M a t h . m a x ( c o n t e n t T y p e . l i n e E n d P o s ,   c o n t e n t T r a n s E n c o d i n g . l i n e E n d P o s )     / /   p o i n t s   t o   f i r s t   \ n   a f t e r   h e a d e r s 
 	 	 } 
 	 	 
 	 	 v a r   f r e e L i n e P o s   =   t h i s . r a w M e s s a g e . i n d e x O f ( " \ n \ n " ,   b e y o n d H e a d e r s P o s ) 
 	 	 v a r   p a r t   =   n e w   M e s s a g e P a r t ( 
 	 	 	 f r e e L i n e P o s + 2 , 
 	 	 	 0 , 
 	 	 	 c o n t e n t T y p e . h e a d e r C o n t e n t , 
 	 	 	 c o n t e n t T r a n s E n c o d i n g . h e a d e r C o n t e n t 
 	 	 ) 
 	 	 
 	 	 v a r   i n n e r B o u n d a r y   =   M e s s a g e C o m p o n e n t s H a n d l e r . g e t B o u n d a r y ( c o n t e n t T y p e . h e a d e r C o n t e n t ) 
 	 	 i f   ( i n n e r B o u n d a r y   ! = =   " " )   { 
 	 	 	 p a r t . m u l t i B o u n d a r y   =   i n n e r B o u n d a r y 
 	 	 	 t h i s . b o u n d a r y L i s t . p u s h ( i n n e r B o u n d a r y ) 
 	 	 	 p a r t . s t a r t - - 
 	 	 } 
 	 	 
 	 	 v a r   s e a r c h a b l e   =   t h i s . d e t e r m i n e S e a r c h a b l e C o n t e n t ( p a r t ) 
 	 	 i f   ( s e a r c h a b l e   = = =   - 1 )   { 
 	 	 	 / /   o n l y ,   e . g . ,   b i n a r y   b a s e 6 4   c o n t e n t   l e f t 
 	 	 	 t h i s . i s P a r s e d   =   t r u e 
 	 	 	 r e t u r n   f a l s e 
 	 	 } 
 	 	 i f   ( s e a r c h a b l e   = = =   - 2 ) 
 	 	 	 / /   p a r s e   r e m a i n i n g   m e s s a g e   c o n t e n t 
 	 	 	 r e t u r n   t h i s . g e t N e x t P a r t ( ) 
 	 	 
 	 	 / /   d e t e r m i n e   e n d   o f   p a r t 
 	 	 t h i s . d e t e r m i n e P a r t E n d ( p a r t ) 
 	 	 	 	 
 	 	 t h i s . p a r t s L i s t . p u s h ( p a r t ) 
 	 	 t h i s . s e a r c h P o s   =   p a r t . e n d   +   1     / /   p r o c e e d   w i t h   n e x t   m e s s a g e   p a r t 
 	 	 t h i s . p a r t I d x + + 
 	 	 r e t u r n   p a r t 
 	 } 
 	 
 	 t h i s . d e t e r m i n e S e a r c h a b l e C o n t e n t   =   f u n c t i o n ( p a r t )   { 
 	 	 / /   b i n a r y   d a t a   o n l y   s e a r c h a b l e   b y   f i l e n a m e   a n d   f i l e   e x t e n s i o n s 
 	 	 i f   ( p a r t . t y p e . i n c l u d e s ( " a p p l i c a t i o n / " ) )   { 
 	 	 	 v a r   f i l e N a m e S t a r t   =   p a r t . t y p e . i n d e x O f ( " n a m e = " ,   1 2 ) 
 	 	 	 v a r   f i l e N a m e E n d   =   p a r t . t y p e . i n d e x O f ( " \ n " ,   f i l e N a m e S t a r t + 5 ) 
 	 	 	 i f   ( f i l e N a m e E n d   <   0 )   f i l e N a m e E n d   =   p a r t . t y p e . l e n g t h 
 	 	 	 p a r t . f i l e N a m e   =   p a r t . t y p e . s u b s t r i n g ( f i l e N a m e S t a r t ,   f i l e N a m e E n d ) 
 	 	 	 r e t u r n   t r u e 
 	 	 } 
 	 	 
 	 	 / /   m u l t i p a r t   c o m p o n e n t   t r e a t e d   a s   e m p t y   m e s s a g e   p a r t 
 	 	 i f   ( p a r t . t y p e . i n c l u d e s ( " m u l t i p a r t / " ) )   { 
 	 	 	 / * v a r   f i r s t C h i l d P o s   =   t h i s . r a w M e s s a g e . i n d e x O f ( p a r t . m u l t i B o u n d a r y ,   p a r t . s t a r t ) ; 
 	 	 	 p a r t . s e t E n d ( f i r s t C h i l d P o s   +   p a r t . m u l t i B o u n d a r y . l e n g t h ) ; * / 
 	 	 	 r e t u r n   t r u e 
 	 	 } 
 	 	 
 	 	 i f   ( p a r t . e n c o d i n g   ! = =   " b a s e 6 4 "   | |   p a r t . t y p e . i n c l u d e s ( " t e x t / " ) ) 
 	 	 	 r e t u r n   t r u e 
 	 	 
 	 	 / /   o n l y   a c c e s s e d   o n c e   p e r   b a s e 6 4   p a r t ,   b e c a u s e   m e s s a g e P a r t s L i s t   e x c l u d e s   t h e m 
 	 	 i f   ( t h i s . b o u n d a r y L i s t . l e n g t h   = = =   0 )   { 
 	 	 	 p a r t . s e t E n d ( t h i s . r a w M e s s a g e . l e n g t h - 1 ) 
 	 	 	 r e t u r n   - 1     / /   w h o l e   m e s s a g e   i s   n o n - t e x t   = >   c a n ' t   s e a r c h 
 	 	 } 
 	 	 
 	 	 v a r   p o s   =   - 1 ,   i   =   t h i s . b o u n d a r y L i s t . l e n g t h - 1 
 	 	 f o r   ( i ;   i > - 1 ;   i - - )   { 
 	 	 	 v a r   p o s   =   t h i s . r a w M e s s a g e . i n d e x O f ( t h i s . b o u n d a r y L i s t [ i ] ,   p a r t . s t a r t ) 
 	 	 	 i f   ( p o s   >   - 1 )   b r e a k 
 	 	 } 
 	 	 t h i s . s e a r c h P o s   =   p o s     / /   s k i p   m e s s a g e   p a r t 
 	 	 
 	 	 / /   r e m o v e   l a s t   b o u n d a r y   f r o m   l i s t   i f   n o t   u s e d   a n y m o r e 
 	 	 i f   ( i   <   t h i s . b o u n d a r y L i s t . l e n g t h - 1 ) 
 	 	 	 t h i s . b o u n d a r y L i s t . p o p ( ) 
 	 	 
 	 	 t h i s . s e a r c h P o s   + =   t h i s . b o u n d a r y L i s t [ i ] . l e n g t h 
 	 	 r e t u r n   - 2 	 / /   d o n ' t   a p p e n d   t o   m e s s a g e P a r t s L i s t 
 	 } 
 	 
 	 t h i s . d e t e r m i n e P a r t E n d   =   f u n c t i o n ( p a r t )   { 
 	 	 / /   d e t e r m i n e   s e a r c h   l i m i t 
 	 	 i f   ( t h i s . b o u n d a r y L i s t . l e n g t h   = = =   0 )   { 
 	 	 	 / /   m e s s a g e   c o n s i s t s   o f   1   p a r t 
 	 	 	 p a r t . s e t E n d ( t h i s . r a w M e s s a g e . l e n g t h - 1 ) 
 	 	 	 r e t u r n 
 	 	 } 
 	 	 
 	 	 / /   d e t e r m i n e   e n d   p o s i t i o n   f o r   s e a r c h   w i t h i n   c u r r e n t   p a r t 
 	 	 i f   ( p a r t . e n d   <   1 )   { 
 	 	 	 v a r   s e a r c h P a r t E n d   =   - 1 ,   i   =   t h i s . b o u n d a r y L i s t . l e n g t h - 1 
 	 	 	 f o r   ( i ;   i > - 1 ;   i - - )   { 
 	 	 	 	 v a r   s e a r c h P a r t E n d   =   t h i s . r a w M e s s a g e . i n d e x O f ( t h i s . b o u n d a r y L i s t [ i ] ,   p a r t . s t a r t ) 
 	 	 	 	 i f   ( s e a r c h P a r t E n d   >   - 1 )   b r e a k 
 	 	 	 } 
 	 	 	 / /   r e m o v e   l a s t   b o u n d a r y   f r o m   l i s t   i f   n o t   u s e d   a n y m o r e 
 	 	 	 i f   ( i   <   t h i s . b o u n d a r y L i s t . l e n g t h - 1 ) 
 	 	 	 	 t h i s . b o u n d a r y L i s t . p o p ( ) 
 	 	 } 
 	 	 e l s e 
 	 	 	 v a r   s e a r c h P a r t E n d   =   p a r t . e n d 
 	 	 
 	 	 i f   ( s e a r c h P a r t E n d - -   = = =   - 1 ) 
 	 	 	 s e a r c h P a r t E n d   =   t h i s . r a w M e s s a g e . l e n g t h - 1     / /   i f   m i s s i n g   f i n a l   b o u n d a r y 
 	 	 	 
 	 	 / /   h a r d e n i n g   a g a i n s t   i n c o n s i s t e n t   b o u n d a r i e s 
 	 	 v a r   l a s t N e w L i n e P o s   =   t h i s . r a w M e s s a g e . l a s t I n d e x O f ( " \ n " ,   s e a r c h P a r t E n d ) 
 	 	 
 	 	 p a r t . s e t E n d ( l a s t N e w L i n e P o s ) 
 	 } ; 
 } 
 
 / * *   e x t r a c t   b o u n d a r y   f r o m   g i v e n   c o n t e n t - t y p e   h e a d e r   s t r i n g   i f   p o s s i b l e * / 
 M e s s a g e C o m p o n e n t s H a n d l e r . g e t B o u n d a r y   =   f u n c t i o n ( s t r ) { 
 	 v a r   b o u n d a r y P o s   =   s t r . i n d e x O f ( " b o u n d a r y = " ) ,   b o u n d a r y   =   " " 
 	 i f   ( b o u n d a r y P o s   ! = =   - 1 )   { 
 	 	 b o u n d a r y   =   s t r . s u b s t r ( b o u n d a r y P o s + 9 ) . t r i m ( ) 
 	 	 i f   ( b o u n d a r y [ 0 ]   = =   ' " ' ) 
 	 	 	 b o u n d a r y   =   b o u n d a r y . s u b s t r ( 1 ,   b o u n d a r y . l e n g t h - 2 )     / /   o m i t   e n c l o s i n g   q u o t e s 
 	 	 / /   o m i t   l e a d i n g   a n d   t r a i l i n g   s e q u e n c e s   o f   ' - ' 
 	 	 b o u n d a r y   =   b o u n d a r y . r e p l a c e ( / ^ - + | - + $ / g ,   ' ' ) 
 	 } 
 	 r e t u r n   b o u n d a r y 
 } 
 
 
 / * *   h t m l   s p e c i a l   e n t i t i e s   d e c o d i n g   f u n c t i o n   * / 
 f u n c t i o n   h t m l D e c o d e U n i c o d e   ( r a w S t r ,   c h a r s e t   =   " " )   { 
 	 v a r   i d x   =   0 ,   r e s   =   ' ' 
 	 v a r   h t m l E n t i t i e s   =   { " & a u m l ; " : " � " ,   " & A u m l ; " : " � " ,   " & o u m l ; " : " � " ,   " & � u m l ; " : " � " ,   " & u u m l ; " : " � " ,   " & U u m l ; " : " � " ,   " & s z l i g ; " : " � " ,   " & z w n j ; " : " " ,   " < \ / ? [ S s ] [ ^ > ] * > " : " " ,   " < \ / ? ( ? : f o n t | F O N T ) [ ^ > ] * > " : " " ,   " & # x 2 0 0 [ c C ] ; " : " "   / * , " & # 2 2 8 ; " : " � " ,   " & # 1 9 6 ; " : " � " ,   " & # 2 4 6 ; " : " � " ,   " & # 2 1 4 ; " : " � " ,   " & # 2 5 2 ; " : " � " ,   " & # 2 2 0 ; " : " � " ,   " & # 2 2 3 ; " : " � " ,   " & # 8 3 6 4 ; " : " � " * / } 
 	 v a r   c u s t o m R p l c   =   { " 8 2 0 4 " : " " }     / /   d e c i m a l   c o d e   p o i n t s   o f ,   e . g . ,   & # 8 2 0 4 ; 
 	 v a r   r e g e x M a p   =   { } 
 	 f o r   ( v a r   s t r   i n   h t m l E n t i t i e s )   { 
 	 	 r e g e x M a p [ s t r ]   =   n e w   R e g E x p ( s t r ,   " g " ) 
 	 } 
 	 
 	 v a r   d e l i m i t e r   =   n u l l ,   m a x D e l i m i t e r O f f s e t   =   0 
 	 
 	 w h i l e   ( i d x   <   r a w S t r . l e n g t h )   { 
 	 	 i f   ( r a w S t r [ i d x ]   = = =   ' & ' )   { 
 	 	 	 / /   s p e c i a l   h t m l   e n t i t i e s 
 	 	 	 d e l i m i t e r   =   ' ; ' 
 	 	 	 m a x D e l i m i t e r O f f s e t   =   7 
 	 	 } 
 	 	 e l s e   i f   ( r a w S t r [ i d x ]   = = =   ' < ' )   { 
 	 	 	 / /   h t m l   t a g s 
 	 	 	 d e l i m i t e r   =   ' > ' 
 	 	 	 m a x D e l i m i t e r O f f s e t   =   3 0 
 	 	 } 
 	 	 e l s e   { 
 	 	 	 r e s   + =   r a w S t r [ i d x + + ] 
 	 	 	 c o n t i n u e 
 	 	 } 
 	 	 
 	 	 / /   d e t e r m i n e   o f f s e t   o f   e n d   d e l i m i t e r 
 	 	 v a r   d e l i m i t e r F o u n d   =   f a l s e 
 	 	 f o r   ( v a r   d e l i m i t e r O f f s e t = 2 ;   d e l i m i t e r O f f s e t   < =   m a x D e l i m i t e r O f f s e t ;   d e l i m i t e r O f f s e t + + )   { 
 	 	 	 i f   ( i d x   +   d e l i m i t e r O f f s e t   > =   r a w S t r . l e n g t h )   b r e a k 
 	 	 	 
 	 	 	 i f   ( r a w S t r [ i d x   +   d e l i m i t e r O f f s e t ]   = = =   d e l i m i t e r )   { 
 	 	 	 	 d e l i m i t e r F o u n d   =   t r u e 
 	 	 	 	 b r e a k 
 	 	 	 } 
 	 	 } 
 	 	 i f   ( d e l i m i t e r F o u n d )   { 
 	 	 	 v a r   e n t i t y   =   ' ' 
 	 	 	 i f   ( d e l i m i t e r   = = =   ' ; '   & &   r a w S t r [ i d x + 1 ]   = = =   ' # ' )   { 
 	 	 	 	 / /   d e c o d e   a l l   s p e c i a l   d e c i m a l   e n t i t i e s   t o   u n i c o d e   c h a r s 
 	 	 	 	 e n t i t y   =   r a w S t r . s u b s t r ( i d x + 2 ,   d e l i m i t e r O f f s e t - 2 ) 
 	 	 	 	 i f   ( c u s t o m R p l c [ e n t i t y ]   ! = =   u n d e f i n e d ) 
 	 	 	 	 	 e n t i t y   =   c u s t o m R p l c [ e n t i t y ] 
 	 	 	 	 e l s e 
 	 	 	 	 	 e n t i t y   =   S t r i n g . f r o m C o d e P o i n t ( e n t i t y   |   0 ) 
 	 	 	 } 
 	 	 	 e l s e   { 
 	 	 	 	 e n t i t y   =   r a w S t r . s u b s t r ( i d x ,   d e l i m i t e r O f f s e t + 1 ) 
 	 	 	 	 f o r   ( v a r   s t r   i n   h t m l E n t i t i e s )   { 
 	 	 	 	 	 / /   r e p l a c e   w i t h   u n i c o d e   c h a r /   e m p t y   s t r i n g   i f   r e g e x   m a t c h e s   h t m l E n t i t i e s 
 	 	 	 	 	 e n t i t y   =   e n t i t y . r e p l a c e ( r e g e x M a p [ s t r ] ,   h t m l E n t i t i e s [ s t r ] ) 
 	 	 	 	 } 
 	 	 	 } 
 	 	 	 r e s   + =   e n t i t y 
 	 	 	 i d x   + =   d e l i m i t e r O f f s e t   +   1 
 	 	 } 
 	 	 e l s e 
 	 	 	 r e s   + =   r a w S t r [ i d x + + ]     / /   n o   s p e c i a l   e n t i t y 
 	 } 
 	 r e t u r n   r e s 
 } 
 
 / * *   b a s e 6 4   d e c o d i n g   f u n c t i o n   * / 
 f u n c t i o n   b 6 4 D e c o d e U n i c o d e   ( r a w S t r ,   c h a r s e t   =   " " )   { 
 	 v a r   a r r   =   b a s e 6 4 H a n d l e r . d e c o d e ( r a w S t r ) 
 	 i f   ( c h a r s e t   = = =   " i s o - 8 8 5 9 - 1 " ) 
 	 	 r e t u r n   d e c o d e B i n a r y A s I s o 8 8 5 9 1 S t r ( a r r ) 
 	 r e t u r n   d e c o d e B i n a r y A s U t f 8 S t r ( a r r ) 
 } 
 
 / * *   Q u o t e d P r i n t a b l e   d e c o d i n g   f u n c t i o n   * / 
 f u n c t i o n   q p D e c o d e U n i c o d e   ( r a w S t r ,   c h a r s e t   =   " " )   { 
 	 v a r   r e s   =   Q u o t e d P r i n t a b l e H a n d l e r . d e c o d e ( r a w S t r ) 
 	 / / m a i l . d i s p l a y D i a l o g ( r e s . a r r . t o S t r i n g ( ) ) ; 
 	 i f   ( c h a r s e t   = = =   " i s o - 8 8 5 9 - 1 " ) 
 	 	 r e t u r n   d e c o d e B i n a r y A s I s o 8 8 5 9 1 S t r ( r e s . a r r ,   r e s . l e n g t h ) 
 	 r e t u r n   d e c o d e B i n a r y A s U t f 8 S t r ( r e s . a r r ,   r e s . l e n g t h ) 
 } 
 
 / * *   t a k e s   U T F - 8   b y t e   a r r a y   a n d   c o n v e r t s   t o   u n i c o d e   s t r i n g   * / 
 f u n c t i o n   d e c o d e B i n a r y A s U t f 8 S t r   ( a r r ,   l e n   =   0 )   { 
 	 v a r   r e s   =   ' ' 
 	 v a r   i d x   =   0 ,   a r r L e n g t h   =   l e n   >   0   ?   l e n   :   a r r . l e n g t h 
 	 	 
 	 / *   1   b y t e   c h a r   0 x 0 0   0 x x x x x x x ;   0 x 8 0   1 0 0 0 0 0 0 0   b i t m a s k 
 	       2   b y t e   c h a r   0 x C 0   1 1 0 x x x x x ;   0 x E 0   1 1 1 0 0 0 0 0   b i t m a s k 
 	       3   b y t e   c h a r   0 x E 0   1 1 1 0 x x x x ;   0 x F 0   1 1 1 1 0 0 0 0   b i t m a s k 
 	       4   b y t e   c h a r   0 x F 0   1 1 1 1 0 x x x ;   0 x F 8   1 1 1 1 1 0 0 0   b i t m a s k 
 	       f o l l o w i n g   b y t e   0 x 8 0   1 0 x x x x x x ;   0 x C 0   1 1 0 0 0 0 0 0   b i t m a s k 
 	 * / 
 	 w h i l e   ( i d x   <   a r r L e n g t h )   { 
 	 	 i f   ( ( a r r [ i d x ]   &   0 x 8 0 )   = = =   0 x 0 0 )   { 	 / /   1   b y t e   c h a r 
 	 	 	 r e s   + =   S t r i n g . f r o m C h a r C o d e ( a r r [ i d x + + ] ) 
 	 	 } 
 	 	 e l s e   i f   ( ( a r r [ i d x ]   &   0 x E 0 )   = = =   0 x C 0   & &   ( a r r [ i d x + 1 ]   &   0 x C 0 )   = = =   0 x 8 0 )   { 
 	 	 	 / /   2   b y t e s   c h a r 
 	 	 	 r e s   + =   S t r i n g . f r o m C h a r C o d e ( ( ( a r r [ i d x + + ] & 0 x 1 F )   < <   6 )   |   ( a r r [ i d x + + ] & 0 x 3 F ) ) 
 	 	 } 
 	 	 e l s e   i f   ( ( a r r [ i d x ]   &   0 x F 0 )   = = =   0 x E 0   & &   ( a r r [ i d x + 1 ]   &   0 x C 0 )   = = =   0 x 8 0 
 	 	 	 	   & &   ( a r r [ i d x + 2 ]   &   0 x C 0 )   = =   0 x 8 0 )   { 
 	 	 	 / /   3   b y t e s   c h a r 
 	 	 	 v a r   c o d e   =   ( ( a r r [ i d x + + ] & 0 x 0 F )   < <   1 2 )   |   ( ( a r r [ i d x + + ] & 0 x 3 F )   < <   6 ) 
 	 	 	     |   ( a r r [ i d x + + ] & 0 x 3 F ) 
 	 	 	 t r y   { 
 	 	 	 	 r e s   + =   S t r i n g . f r o m C o d e P o i n t ( c o d e ) 
 	 	 	 }   c a t c h   ( e ) { 
 	 	 	 	 / / c o n s o l e . l o g ( ' d e c o d e d   p a r t :   ' + r e s ) 
 	 	 	 	 / / c o n s o l e . l o g ( ' e r r o r   3   b y t e s :   ' + e   +   ' ,   ' +   c o d e . t o S t r i n g ( 1 6 ) ) 
 	 	 	 	 r e s   + =   c o d e   = =   0 x E F B B B F   ?   ' \ u F E F F '   :   ' \ u F F F D ' 
 	 	 	 } 
 	 	 } 
 	 	 e l s e   i f   ( ( a r r [ i d x ]   &   0 x F 8 )   = = =   0 x F 0   & &   ( a r r [ i d x + 1 ]   &   0 x C 0 )   = = =   0 x 8 0 
 	 	 	   & &   ( a r r [ i d x + 2 ]   &   0 x C 0 )   = = =   0 x 8 0   & &   ( a r r [ i d x + 3 ]   &   0 x C 0 )   = = =   0 x 8 0 )   { 
 	 	 	   / /   4   b y t e s   c h a r 
 	 	 	 v a r   c o d e   =   ( ( a r r [ i d x + + ] & 0 x 0 7 )   < <   1 8 )   |   ( ( a r r [ i d x + + ] & 0 x 3 F )   < <   1 2 )   |   ( ( a r r [ i d x + + ] & 0 x 3 F )   < <   6 ) 
 	 	 	   	 |   ( a r r [ i d x + + ] & 0 x 3 F ) 
 	 	 	 t r y   { 
 	 	 	 	 r e s   + =   S t r i n g . f r o m C o d e P o i n t ( c o d e ) 
 	 	 	 }   c a t c h   ( e )   { 
 	 	 	     	 / / c o n s o l e . l o g ( ' d e c o d e d   p a r t :   ' + r e s ) 
 	 	 	 	 / / c o n s o l e . l o g ( ' e r r o r   4   b y t e s :   ' + e   +   ' ,   ' +   c o d e . t o S t r i n g ( 1 6 ) ) 
 	 	 	 	 r e s   + =   c o d e   = =   0 x E F B B B F   ?   ' \ u F E F F '   :   ' \ u F F F D ' 
 	 	 	 } 
 	 	 } 
 	 	 e l s e   { 
 	 	 	 r e s   + =   ' \ u F F F D ' 
 	 	 	 i d x + + 
 	 	 } 
 	 } 
 	 / / c o n s o l e . l o g ( ' d e c o d e d   u n i c o d e :   ' + r e s ) 
 	 r e t u r n   r e s 
 } 
 
 / * *   t a k e s   I S O   8 8 5 9 - 1   ( L a t i n - 1 )   b y t e   a r r a y   a n d   c o n v e r t s   t o   u n i c o d e   s t r i n g   * / 
 f u n c t i o n   d e c o d e B i n a r y A s I s o 8 8 5 9 1 S t r   ( a r r ,   l e n   =   0 )   { 
 	 v a r   r e s   =   ' ' 
 	 v a r   i d x   =   0 ,   a r r L e n g t h   =   l e n   >   0   ?   l e n   :   a r r . l e n g t h 
 	 
 	 f o r   ( i d x ;   i d x < a r r L e n g t h ;   i d x + + )   { 
 	 	 r e s   + =   S t r i n g . f r o m C h a r C o d e ( a r r [ i d x ] ) 
 	 } 
 	 r e t u r n   r e s 
 } 
 
 / /   b a s e d   o n   b a s e 6 4 - j s   l i b   a t   h t t p s : / / g i t h u b . c o m / b e a t g a m m i t / b a s e 6 4 - j s 
 v a r   b a s e 6 4 H a n d l e r   =   ( f u n c t i o n   ( )   { 
 	 v a r   l o o k u p   =   [ ] 
 	 v a r   r e v L o o k u p   =   [ ] 
 	 v a r   A r r   =   t y p e o f   U i n t 8 A r r a y   ! = =   ' u n d e f i n e d '   ?   U i n t 8 A r r a y   :   A r r a y 
 
 	 v a r   c o d e   =   ' A B C D E F G H I J K L M N O P Q R S T U V W X Y Z a b c d e f g h i j k l m n o p q r s t u v w x y z 0 1 2 3 4 5 6 7 8 9 + / ' 
 	 f o r   ( v a r   i   =   0 ,   l e n   =   c o d e . l e n g t h ;   i   <   l e n ;   + + i )   { 
     	 	 l o o k u p [ i ]   =   c o d e [ i ] 
     	 	 r e v L o o k u p [ c o d e . c h a r C o d e A t ( i ) ]   =   i 
 	 } 
 
 	 r e v L o o k u p [ ' - ' . c h a r C o d e A t ( 0 ) ]   =   6 2 
 	 r e v L o o k u p [ ' _ ' . c h a r C o d e A t ( 0 ) ]   =   6 3 
 
 	 f u n c t i o n   p l a c e H o l d e r s C o u n t   ( b 6 4 )   { 
     	 	 v a r   l e n   =   b 6 4 . l e n g t h 
     	 	 i f   ( l e n   %   4   >   0   & &   ( l e n + 2 )   %   4   >   0 )   { 
 	 	 m a i l . d i s p l a y D i a l o g ( " e r r o r " + l e n + '   ' + b 6 4 . s l i c e ( - 5 0 ) ) ; 
         	   t h r o w   n e w   E r r o r ( ' I n v a l i d   s t r i n g .   L e n g t h   ' + l e n + '   m u s t   b e   a   m u l t i p l e   o f   4 ' ) 
     	 	 } 
     	 	 r e t u r n   b 6 4 [ l e n   -   2 ]   = = =   ' = '   ?   2   :   b 6 4 [ l e n   -   1 ]   = = =   ' = '   ?   1   :   0 
 	 } 
 
 	 f u n c t i o n   b y t e L e n g t h   ( b 6 4 )   { 
     	 	 / /   b a s e 6 4   i s   4 / 3   +   u p   t o   t w o   c h a r a c t e r s   o f   t h e   o r i g i n a l   d a t a 
     	 	 r e t u r n   ( b 6 4 . l e n g t h   *   3   /   4 )   -   p l a c e H o l d e r s C o u n t ( b 6 4 ) 
 	 } 
 
 	 r e t u r n   { d e c o d e :   f u n c t i o n   ( b 6 4 )   { 
 	 	 v a r   i ,   j ,   l ,   t m p ,   p l a c e H o l d e r s ,   a r r 
 	 	 v a r   l e n   =   b 6 4 . l e n g t h 
 	 	 t r y   { 
 	 	 	 p l a c e H o l d e r s   =   p l a c e H o l d e r s C o u n t ( b 6 4 ) 
 	 	 }   c a t c h   ( e r r )   { 
 	 	 	 m a i l . d i s p l a y D i a l o g ( " B 6 4   d e c o d e   e r r o r :   "   +   e r r . m e s s a g e ) ; 
 	 	 	 r e t u r n   n u l l 
 	 	 } 
 	 	 a r r   =   n e w   A r r ( ( l e n   *   3   /   4 )   -   p l a c e H o l d e r s ) 
 
 	 	 / /   i f   t h e r e   a r e   p l a c e h o l d e r s ,   o n l y   g e t   u p   t o   t h e   l a s t   c o m p l e t e   4   c h a r s 
 	 	 l   =   p l a c e H o l d e r s   >   0   ?   l e n   -   4   :   l e n 
 	 	 v a r   L   =   0 
 
 	 	 f o r   ( i   =   0 ,   j   =   0 ;   i   <   l ;   i   + =   4 ,   j   + =   3 )   { 
 	 	 	 t m p   =   ( r e v L o o k u p [ b 6 4 . c h a r C o d e A t ( i ) ]   < <   1 8 )   |   ( r e v L o o k u p [ b 6 4 . c h a r C o d e A t ( i   +   1 ) ]   < <   1 2 )   |   ( r e v L o o k u p [ b 6 4 . c h a r C o d e A t ( i   +   2 ) ]   < <   6 )   |   r e v L o o k u p [ b 6 4 . c h a r C o d e A t ( i   +   3 ) ] 
 	 	 	 a r r [ L + + ]   =   ( t m p   > >   1 6 )   &   0 x F F 
 	 	 	 a r r [ L + + ]   =   ( t m p   > >   8 )   &   0 x F F 
 	 	 	 a r r [ L + + ]   =   t m p   &   0 x F F 
 	 	 } 
 
 	 	 i f   ( p l a c e H o l d e r s   = = =   2 )   { 
 	 	 	 t m p   =   ( r e v L o o k u p [ b 6 4 . c h a r C o d e A t ( i ) ]   < <   2 )   |   ( r e v L o o k u p [ b 6 4 . c h a r C o d e A t ( i   +   1 ) ]   > >   4 ) 
 	 	 	 a r r [ L + + ]   =   t m p   &   0 x F F 
 	 	 }   e l s e   i f   ( p l a c e H o l d e r s   = = =   1 )   { 
 	 	 	 t m p   =   ( r e v L o o k u p [ b 6 4 . c h a r C o d e A t ( i ) ]   < <   1 0 )   |   ( r e v L o o k u p [ b 6 4 . c h a r C o d e A t ( i   +   1 ) ]   < <   4 )   |   ( r e v L o o k u p [ b 6 4 . c h a r C o d e A t ( i   +   2 ) ]   > >   2 ) 
 	 	 	 a r r [ L + + ]   =   ( t m p   > >   8 )   &   0 x F F 
 	 	 	 a r r [ L + + ]   =   t m p   &   0 x F F 
 	 	 } 
 	 	 r e t u r n   a r r } 
 	 } 
 } ) ( ) 
 
 / /   b a s e d   o n   h t t p s : / / g i t h u b . c o m / r o n o m o n / q u o t e d - p r i n t a b l e / b l o b / m a s t e r / i n d e x . j s   a n d   h t t p s : / / g i t h u b . c o m / m a t h i a s b y n e n s / q u o t e d - p r i n t a b l e / b l o b / m a s t e r / s r c / q u o t e d - p r i n t a b l e . j s 
 v a r   Q u o t e d P r i n t a b l e H a n d l e r   =   ( f u n c t i o n   ( )   { 
 	 v a r   A r r   =   t y p e o f   U i n t 8 A r r a y   ! = =   ' u n d e f i n e d '   ?   U i n t 8 A r r a y   :   A r r a y 
 	 v a r   d e c o d e T a b l e   =   ( f u n c t i o n ( ) { 
 	 	 v a r   a l p h a b e t   =   ' 0 1 2 3 4 5 6 7 8 9 A B C D E F a b c d e f ' 
     	 	 v a r   t a b l e   =   n e w   A r r ( 2 5 6 ) 
     	 	 f o r   ( v a r   i n d e x   =   0 ,   l e n g t h   =   a l p h a b e t . l e n g t h ;   i n d e x   <   l e n g t h ;   i n d e x + + )   { 
         	 	 v a r   c h a r   =   a l p h a b e t [ i n d e x ] ; 
         	 / /   A d d   1   t o   a l l   v a l u e s   s o   t h a t   w e   c a n   d e t e c t   h e x   d i g i t s   w i t h   t h e   s a m e   t a b l e . 
         	 / /   S u b t r a c t   1   w h e n   n e e d e d   t o   g e t   t o   t h e   i n t e g e r   v a l u e   o f   t h e   h e x   d i g i t . 
         	 	 t a b l e [ c h a r . c h a r C o d e A t ( 0 ) ]   =   p a r s e I n t ( c h a r ,   1 6 )   +   1 ; 
     	 	 } 
     	 	 r e t u r n   t a b l e 
     	 } ) ( ) 
 	 
 	 r e t u r n   { d e c o d e :   f u n c t i o n   ( s r c ,   u s e Q E n c o d i n g   =   f a l s e )   { 
 	 	 v a r   g e t L i n e B r e a k S i z e   =   f u n c t i o n ( ) { 
 	 	 	 i f   ( b y t e S r c [ s I d x ]   = = =   1 3   & &   s I d x + 1   <   l e n   & &   b y t e S r c [ s I d x + 1 ]   = = =   1 0 ) 
 	 	 	 	 r e t u r n   2 
 	 	 	 i f   ( b y t e S r c [ s I d x ]   = = =   1 3   | |   b y t e S r c [ s I d x ]   = = =   1 0 ) 
 	 	 	 	 r e t u r n   1 
 	 	 	 r e t u r n   0 
 	 	 } 
 	 	 v a r   l e n   =   s r c . l e n g t h ,   b y t e S r c   =   n e w   A r r ( l e n ) ,   r e s   =   n e w   A r r ( l e n ) 
 	 	 
 	 	 / /   c o n v e r t   c h a r   t o   b i n a r y 
 	 	 f o r   ( v a r   i = 0 ;   i < l e n ;   i + + ) 
 	 	 	 b y t e S r c [ i ]   =   s r c [ i ] . c h a r C o d e A t ( 0 ) 
 	 	 
 	 	 v a r   s I d x   =   0 ,   r e s I d x   =   0 
 	 	 w h i l e   ( s I d x   <   l e n )   { 
 	 	 	 i f   ( ( b y t e S r c [ s I d x ] )   = = =   6 1 / *   ' = '   * /   & &   s I d x + 2   <   l e n 
 	 	 	     & &   d e c o d e T a b l e [ b y t e S r c [ s I d x + 1 ] ] 
 	 	 	     & &   d e c o d e T a b l e [ b y t e S r c [ s I d x + 2 ] ] )   { 
 	 	 	 	 r e s [ r e s I d x + + ]   =   ( ( d e c o d e T a b l e [ b y t e S r c [ s I d x + 1 ] ]   -   1 )   < <   4 ) 
 	 	 	 	   +   ( ( d e c o d e T a b l e [ b y t e S r c [ s I d x + 2 ] ]   -   1 ) ) 
 	 	 	 	 s I d x   + =   3 
 	 	 	 } 
 	 	 	 e l s e   i f   ( b y t e S r c [ s I d x ]   = = =   1 3 / *   C R   * /   | |   b y t e S r c [ s I d x ]   = = =   1 0 / *   L F   * / )   { 
 	 	 	 	 / /   o v e r w r i t e   t r a i l i n g   w h i t e s p a c e s   T A B / S P A C E 
 	 	 	 	 v a r   r e w i n d I d x   =   s I d x 
 	 	 	 	 w h i l e   ( r e s I d x   >   0   & &   r e w i n d I d x   >   0 
 	 	 	 	     & &   ( b y t e S r c [ r e w i n d I d x - 1 ]   = = =   9   | |   b y t e S r c [ r e w i n d I d x - 1 ]   = = =   3 2 ) )   { 
 	 	 	 	 	 r e s I d x - - 
 	 	 	 	 	 r e w i n d I d x - - 
 	 	 	 	 } 
 	 	 	 	 i f   ( r e s I d x   >   0   & &   r e w i n d I d x   >   0   & &   b y t e S r c [ r e w i n d I d x - 1 ]   = = =   6 1 )   { 
 	 	 	 	 	 / /   s o f t   l i n e   b r e a k   w i t h   ' = '   a s   l a s t   n o n - w h i t e s p a c e   = >   t r a n s p o r t   e n c o d i n g 
 	 	 	 	 	 r e s I d x - - 
 	 	 	 	 	 s I d x   + =   g e t L i n e B r e a k S i z e ( ) 
 	 	 	 	 } 
 	 	 	 	 e l s e   { 
 	 	 	 	 	 / /   a d d   l i n e   b r e a k   C R   a n d / o r   L F 
 	 	 	 	 	 f o r   ( v a r   i   =   g e t L i n e B r e a k S i z e ( ) ;   i > 0 ;   i - - ) 
 	 	 	 	 	 	 r e s [ r e s I d x + + ]   =   b y t e S r c [ s I d x + + ] 
 	 	 	 	 } 
 	 	 	 } 
 	 	 	 e l s e   i f   ( u s e Q E n c o d i n g   = = =   t r u e   & &   b y t e S r c [ s I d x ]   = = =   9 5 )   { 
 	 	 	 	 / /   r e p l a c e   ' _ '   w i t h   '   ' 
 	 	 	 	 r e s [ r e s I d x + + ]   =   3 2 
 	 	 	 	 s I d x + + 
 	 	 	 } 
 	 	 	 e l s e   { 
 	 	 	 	 r e s [ r e s I d x + + ]   =   b y t e S r c [ s I d x + + ] 
 	 	 	 } 
 	 	 } 
 	 	 
 	 	 / /   r e m o v e   t r a i l i n g   w h i t e s p a c e   p a d d i n g 
 	 	 v a r   r e w i n d I d x   =   s I d x 
 	 	 w h i l e   ( r e s I d x   >   0   & &   r e w i n d I d x   >   0 
 	 	     & &   ( b y t e S r c [ r e w i n d I d x - 1 ]   = = =   9   | |   b y t e S r c [ r e w i n d I d x - 1 ]   = = =   3 2 ) )   { 
 	 	 	 r e s I d x - - 
 	 	 	 r e w i n d I d x - - 
 	 	 } 
 	 	 
 	 	 r e t u r n   { a r r :   r e s ,   l e n g t h :   r e s I d x + 1 } } 
 	 } 
 } ) ( )                              ̌jscr  ��ޭ