$(function() {
  function removeAccents ( data ) {
    return data
      .replace( /á/g, 'a' )
      .replace( /à/g, 'a' )
      .replace( /ả/g, 'a' )
      .replace( /ã/g, 'a' )
      .replace( /ạ/g, 'a' )
      .replace( /â/g, 'a' )
      .replace( /ấ/g, 'a' )
      .replace( /ầ/g, 'a' )
      .replace( /ẩ/g, 'a' )
      .replace( /ẫ/g, 'a' )		  
      .replace( /ậ/g, 'a' )
      .replace( /ă/g, 'a' )
      .replace( /ắ/g, 'a' )
      .replace( /ằ/g, 'a' )
      .replace( /ẳ/g, 'a' )
      .replace( /ẵ/g, 'a' )		  
      .replace( /ặ/g, 'a' )
              
      .replace( /é/g, 'e' )
      .replace( /è/g, 'e' )
      .replace( /ẻ/g, 'e' )
      .replace( /ẽ/g, 'e' )
      .replace( /ẹ/g, 'e' )
      .replace( /ê/g, 'e' )
      .replace( /ế/g, 'e' )
      .replace( /ề/g, 'e' )
      .replace( /ể/g, 'e' )
      .replace( /ễ/g, 'e' )
      .replace( /ệ/g, 'e' )
              
      .replace( /í/g, 'i' )
      .replace( /ì/g, 'i' )
      .replace( /ỉ/g, 'i' )
      .replace( /ĩ/g, 'i' )
      .replace( /ị/g, 'i' )
                                              
      .replace( /ó/g, 'o' )
      .replace( /ò/g, 'o' )
      .replace( /ỏ/g, 'o' )
      .replace( /õ/g, 'o' )
      .replace( /ọ/g, 'o' )
      .replace( /ô/g, 'o' )
      .replace( /ố/g, 'o' )
      .replace( /ồ/g, 'o' )
      .replace( /ổ/g, 'o' )
      .replace( /ỗ/g, 'o' )		  
      .replace( /ộ/g, 'o' )
      .replace( /ơ/g, 'o' )
      .replace( /ớ/g, 'o' )
      .replace( /ờ/g, 'o' )
      .replace( /ở/g, 'o' )
      .replace( /ỡ/g, 'o' )		  
      .replace( /ợ/g, 'o' )
              
      .replace( /ú/g, 'u' )
      .replace( /ù/g, 'u' )
      .replace( /ủ/g, 'u' )
      .replace( /ũ/g, 'u' )
      .replace( /ụ/g, 'u' )
      .replace( /ư/g, 'u' )
      .replace( /ứ/g, 'u' )
      .replace( /ừ/g, 'u' )
      .replace( /ử/g, 'u' )
      .replace( /ữ/g, 'u' )
      .replace( /ự/g, 'u' ) ;
  }

  var searchType = jQuery.fn.DataTable.ext.type.search;
   
  searchType.string = function ( data ) {
      return ! data ?
          '' :
          typeof data === 'string' ?
              removeAccents( data ) :
              data;
  };
   
  searchType.html = function ( data ) {
      return ! data ?
          '' :
          typeof data === 'string' ?
              removeAccents( data.replace( /<.*?>/g, '' ) ) :
              data;
  };
});
