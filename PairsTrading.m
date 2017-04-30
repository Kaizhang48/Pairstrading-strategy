
HS300_advanced=(xlsread('融资融券标的中证800日线数据.xlsx','历史行情'))';
[CLOSE,txt]=xlsread('融资融券标的收盘.xlsx','sheet1');%成分股收盘价
[~,STIU]=xlsread('融资标的股票交易状态.xlsx','历史行情');
STIU=STIU';
STIU=STIU(2:end,5:end);
[~,ll]=find(cellfun('isempty',STIU)==1,1,'first');
STIU=STIU(:,1:ll-1);
[aa,bb]=size(STIU);
STIUATION=ones(aa,bb).*9999;
for i=1:aa
    for j=1:bb
        if strcmp(STIU{i,j},'正常交易')||strcmp(STIU{i,j},'复牌')||strcmp(STIU{i,j},'盘中停牌')||strcmp(STIU{i,j},'停牌一小时')||strcmp(STIU{i,j},'停牌半天')||strcmp(STIU{i,j},'停牌半小时')
            STIUATION(i,j)=1;
        elseif strcmp(STIU{i,j},'暂停上市')||strcmp(STIU{i,j},'连续停牌')||strcmp(STIU{i,j},'停牌一天')||strcmp(STIU{i,j},'未上市')
            STIUATION(i,j)=0;
        end
    end
end
xlswrite('C:\csvdata\Pair_STIUATION.xlsx', STIUATION ,'sheet1')
OPEN=(xlsread('融资融券标的开盘.xlsx','sheet1'))';
CLOSE(isnan(CLOSE))=0;
CLOSE=CLOSE';
%标准化价格
% r(i)=log(p(i))-log(p(i-1))
% SP(t)表示第t天的标准价格,SP(t)=sum(1+r(i):i=1~t)
LOGreturn=LOGreturn_maker(CLOSE);
LOGreturn(isnan(LOGreturn))=0;
SP=cumprod((1+LOGreturn),2);
secName=txt(3,2:end)';
tradeDate=txt(5:end,1)';%股票日期列表,横向量
tradeDate=tradeDate(1:find(cellfun('isempty',tradeDate)==1,1,'first')-1);
tradeDate=tradeDate(1,1:end);
OPEN(isnan(OPEN))=0;
% load('PAIRnewnew.mat')
%----------------------------------------------------------------------------导入数据
%----------------------------------------------------------------------------构建账户信息
Observe=220;
TOP=500;
storageRoom=5;
stamptax_rate=0.001;    
commision_rate=0.00025;
lowest_commision=5;
pre_pairNumber=80;
pairNumber=40;
confidence_coeff=3;
changeMonth=3;
Loanthreshhold=0.2;%融券平仓止损点
%Observe=480
%storagerRoom=15
%---------------------------------------------------------------------------账户信息构建完毕
OPEN=OPEN(1:TOP,:);
secName=secName(1:TOP,:);
CLOSE=CLOSE(1:TOP,:);
STIUATION=STIUATION(1:TOP,:);
[s,row]=size(CLOSE);
capital=zeros(1,row);
Loan_capital=zeros(1,row);
cash=zeros(1,row);
cash(1,1:Observe)=200000;
universe=cell(pairNumber,length(tradeDate));

benchmarkCLOSE=HS300_advanced(4,:);%对应指数收盘价
benchmarkOPEN=HS300_advanced(1,:);%对应指数开盘价
storage=zeros(storageRoom,row);%行是股票,列是时间,中间的数值是股票的位数
storage_Loan=zeros(storageRoom,row);%融券的仓位 买的股票在storage里,融的券在storage_Loan里
each_lamda=zeros(s,row);
buy_record=cell(storageRoom,row);
sale_record=cell(storageRoom,row);
buyLoan_record=cell(storageRoom,row);
saleLoan_record=cell(storageRoom,row);
%----------------------------融券情况
buyLoan=zeros(s,row);
saleLoan=zeros(s,row);
%----------------------------融券情况
Condition=zeros(s,row);
storage_name=cell(size(storage));
storage_Loan_name=cell(size(storage));
buy=zeros(s,row);
secLoanValue=zeros(s,row);
sale=zeros(s,row);
volume=zeros(s,row);%s,row是CLOSE的行和列
Loan_volume=zeros(s,row);
perreturn=zeros(s,row);
perreturn_rate=zeros(s,row);
dayreturn=zeros(1,row);
stamptax=zeros(s,row);%印花税,卖的时候才收取
buy_commision=zeros(s,row);%佣金,买卖都收取,佣金有最小值lowest_commision
sale_commision=zeros(s,row);

benchmark_rt=(benchmarkCLOSE(1,Observe+1:end)-benchmarkOPEN(1,Observe+1))./benchmarkOPEN(1,Observe+1);
for Date=Observe:(length(tradeDate)-1)%循环每天
    xc=Date
    histwindow=120;
%-------------------------------------------更新每日账户信息
    storage_name(:,Date+1)=storage_name(:,Date);
    storage_Loan_name(:,Date+1)=storage_Loan_name(:,Date);
    storage(:,Date+1)=storage(:,Date);
    storage_Loan(:,Date+1)=storage_Loan(:,Date);
    volume(:,Date+1)=volume(:,Date);
    Loan_volume(:,Date+1)=Loan_volume(:,Date);
    cash(1,Date+1)=cash(1,Date);
    secLoanValue(:,Date+1)=secLoanValue(:,Date);

    universe(:,Date+1)=universe(:,Date);
%--------------------------------------------更新完毕

%----------------------------------------------构建股票池
    if mod(Date-Observe,20.*changeMonth)==0%月为单位更新股票池
        today=tradeDate(1,Date);
%         distance=ones(length(secName),length(secName)).*10000000;
%         distance_origin=ones(length(secName),length(secName)).*10000000;
        distance=ones(length(secName),length(secName)).*inf;
        distance_origin=ones(length(secName),length(secName)).*inf;
        universe(:,Date+1)=cell(pairNumber,1);
 %---------------------------------------------选取距离最小的
        for i=1:length(secName)-1
            for j=i+1:length(secName)%检索每一对股票的距离
                temp1=SP(i,Date-histwindow:Date)-SP(j,Date-histwindow:Date);
                temp2=power(temp1,2);
                temp3=sum(temp2);%算出规定时间窗口内,两个标准化以后的股票价格时间序列的最小二乘法中的距离
                distance(i,j)=temp3;
                distance_origin(i,j)=temp3;
            end
            if prod(SP(i,1:Date))==1%如果没上市
                distance(i,:)=inf;
                distance(:,i)=inf;
                distance_origin(i,:)=inf;
                distance_origin(:,i)=inf;
                %若股票没有上市,则不允许与之配对
            end
        end%universe=cell(pairNumber,length(tradeDate));
        preuniverse=zeros(pre_pairNumber,2);%初步筛选出距离最小的
        for i=1:pre_pairNumber
            [a,b]=find(distance==min(min(distance)),1,'last');
            preuniverse(i,:)=[a,b];
            distance(a,:)=inf;
            distance(:,a)=inf;
            distance(:,b)=inf;
            distance(b,:)=inf;
        end
        adfuniverse=[];%在找出的距离小的配对中找出有平稳时间序列的配对(通过adftest的配对)
        for j=1:pre_pairNumber
            A=SP(preuniverse(j,1),Date-histwindow:Date);
            B=SP(preuniverse(j,2),Date-histwindow:Date);
            for c=1:length(A)                        
                h1=adftest(A);
                h2=adftest(B);
                if h1==1&&h2==1
                    adfuniverse=[adfuniverse;preuniverse(j,:)];
                    break;
                elseif h1==0&&h2==0
                    A=diff(A);
                    B=diff(B);
                    if sum(A)==0||sum(5)==0
                        %其中有股票长时间连续停牌
                        break;
                    end
                elseif (~(h1==1&&h2==1))&&(h1==1||h2==1)
                    break;
                end
            end            
        end

        for i=1:length(adfuniverse)%对挑选出的具有平稳时间序列的配对做协整检验,找出具有协整效应的配对
            y=[(SP(adfuniverse(i,1),Date-histwindow:Date))',(SP(adfuniverse(i,2),Date-histwindow:Date))'];
            h=egcitest(y);
            nullloc=cellfun('isempty',universe(:,Date+1)); %universe是cell,cellfun是cellfunction的意思
            null_first=find(nullloc==1,1,'first');%=1为空
            if length(find(nullloc==1))>0
                if h==1
                    universe{null_first,Date+1}=adfuniverse(i,:);
                end
            else
                break;
            end
        end
    end
%------------------------------------------------构建股票池完毕
%-----------------------------------------------卖出信号   
    for p=1:storageRoom
        if  storage(p,Date+1)~=0&&storage_Loan(p,Date+1)~=0
            %每对第一个是买,第二个是融
            mai=storage(p,Date+1);
            rong=storage_Loan(p,Date+1);
            
            STOPprice=round(CLOSE(mai,Date).*1.1.*100)./100;
            STOPDprice=round(CLOSE(mai,Date).*0.9.*100)./100;
            STOPLoanprice=round(CLOSE(rong,Date).*1.1.*100)./100;
            STOPLoanDprice=round(CLOSE(rong,Date).*0.9.*100)./100;
            if OPEN(rong,Date+1)<STOPLoanprice&&OPEN(rong,Date+1)>STOPLoanDprice&& OPEN(mai,Date+1)<STOPprice&&OPEN(mai,Date+1)>STOPDprice
                if STIUATION(mai,Date+1)==1&&STIUATION(rong,Date+1)==1%无停牌
                    buydate=find(buy(mai,:)~=0, 1, 'last' );%最近一次买的日期
                    if Condition(mai,buydate)==1%买的时候根据的是lembda_positive,做多小的,做空大的 
%                        Diff=CLOSE(rong,Date-histwindow:Date)-CLOSE(mai,Date-histwindow:Date);
                        lemda=each_lamda(mai,buydate);%mean(Diff)+confidence_coeff.*std(Diff);                            
                        if CLOSE(rong,Date)-CLOSE(mai,Date)<lemda||(-(Loan_volume(rong,buydate).*(OPEN(rong,buydate)-OPEN(rong,Date+1)))./(Loan_volume(rong,buydate).*OPEN(rong,buydate)))>=Loanthreshhold
                    %若出现卖点,卖出小的
                            sale_commision(mai,Date+1)=(volume(mai,buydate).*OPEN(mai,Date+1)).*commision_rate;
                            if sale_commision(mai,Date+1)<lowest_commision                           
                                sale_commision(mai,Date+1)=lowest_commision;
                            end
                            stamptax(mai,Date+1)=(volume(mai,buydate).*OPEN(mai,Date+1)).*stamptax_rate;
                            cash(1,Date+1)=cash(1,Date+1)+volume(mai,buydate).*OPEN(mai,Date+1)-stamptax(mai,Date+1)-sale_commision(mai,Date+1);                        
                            sale(mai,Date+1)=OPEN(mai,Date+1);
                            sale_record(p,Date+1)=secName(mai,1);

                      %卖出融来的大的
                            saleLoan(rong,Date+1)=OPEN(rong,Date+1);
                            sale_commision(rong,Date+1)=(Loan_volume(rong,buydate).*OPEN(rong,Date+1)).*commision_rate;
                            if sale_commision(rong,Date+1)<lowest_commision                           
                                sale_commision(rong,Date+1)=lowest_commision;
                            end
                            stamptax(rong,Date+1)=(Loan_volume(rong,buydate).*OPEN(rong,Date+1)).*stamptax_rate; 
                            temp=Loan_volume(rong,buydate).*(OPEN(rong,buydate)-OPEN(rong,Date+1))- stamptax(rong,Date+1)-sale_commision(rong,Date+1);
                            cash(1,Date+1)=cash(1,Date+1)+temp;                        
                            saleLoan_record(p,Date+1)=secName(rong,1);                       
                            perreturn(mai,Date+1)=(OPEN(mai,Date+1)-OPEN(mai,buydate)).*volume(mai,buydate)-stamptax(mai,Date+1)-sale_commision(mai,Date+1)-buy_commision(mai,buydate)+temp;
                            perreturn_rate(mai,Date+1)=perreturn(mai,Date+1)./(volume(mai,buydate).*OPEN(mai,buydate)+buy_commision(mai,buydate));
                            %更新矩阵信息
                            volume(mai,Date+1)=0;
                            volume(rong,Date+1)=0;
                            storage(p,Date+1)=0;
                            storage_name{p,Date+1}=[];
                            storage_Loan(p,Date+1)=0;
                            storage_Loan_name{p,Date+1}=[];
                        end
                    elseif Condition(mai,buydate)==2%买的时候是根据lemda_negative
                        %做多大的,做空小的
                        %每对第一个为买,第二个为融,也就是说在condition2中,第一个是大,第二个是小
%                         Diff=CLOSE(mai,Date-histwindow:Date)-CLOSE(rong,Date-histwindow:Date);
%                         lemda=mean(Diff);
                        lemda=each_lamda(mai,buydate);%mean(Diff)-confidence_coeff.*std(Diff);                            
                        if CLOSE(mai,Date)-CLOSE(rong,Date)>lemda||(-(Loan_volume(rong,buydate).*(OPEN(rong,buydate)-OPEN(rong,Date+1)))./(Loan_volume(rong,buydate).*OPEN(rong,buydate)))>=Loanthreshhold
                    %若出现卖点,卖出大的
                            sale_commision(mai,Date+1)=(volume(mai,buydate).*OPEN(mai,Date+1)).*commision_rate;
                            if sale_commision(mai,Date+1)<lowest_commision                           
                                sale_commision(mai,Date+1)=lowest_commision;
                            end
                            stamptax(mai,Date+1)=(volume(mai,buydate).*OPEN(mai,Date+1)).*stamptax_rate;
                            cash(1,Date+1)=cash(1,Date+1)+volume(mai,buydate).*OPEN(mai,Date+1)-stamptax(mai,Date+1)-sale_commision(mai,Date+1);                       
                            sale(mai,Date+1)=OPEN(mai,Date+1);
                            sale_record(p,Date+1)=secName(mai,1);

                      %卖出融来的小的
                            saleLoan(rong,Date+1)=OPEN(rong,Date+1);
                            sale_commision(rong,Date+1)=(volume(rong,buydate).*OPEN(rong,Date+1)).*commision_rate;
                            if sale_commision(rong,Date+1)<lowest_commision                           
                                sale_commision(rong,Date+1)=lowest_commision;

                            end
                            stamptax(rong,Date+1)=(Loan_volume(rong,buydate).*OPEN(rong,Date+1)).*stamptax_rate; 
                            temp=Loan_volume(rong,buydate).*(OPEN(rong,buydate)-OPEN(rong,Date+1))- stamptax(rong,Date+1)-sale_commision(rong,Date+1);
                            cash(1,Date+1)=cash(1,Date+1)+temp;                        
                            saleLoan_record(p,Date+1)=secName(rong,1);
                            perreturn(mai,Date+1)=(OPEN(mai,Date+1)-OPEN(mai,buydate)).*volume(mai,buydate)-stamptax(mai,Date+1)-sale_commision(mai,Date+1)-buy_commision(mai,buydate)+temp;
                            perreturn_rate(mai,Date+1)=perreturn(mai,Date+1)./(volume(mai,buydate).*OPEN(mai,buydate)+buy_commision(mai,buydate));
                            %更新矩阵信息
                            volume(mai,Date+1)=0;
                            volume(rong,Date+1)=0;
                            storage(p,Date+1)=0;
                            storage_name{p,Date+1}=[];
                            storage_Loan(p,Date+1)=0;
                            storage_Loan_name{p,Date+1}=[];

                        end
                    end
                end
            end

        end
    end
%-----------------------------------------------------------------卖出信号       
    for pair=1:pairNumber%遍历universe中所有的配对  
        nullloc=cellfun('isempty',universe(pair,Date+1));
        if nullloc==0%确定元胞不为空
%--------------------------------------------------------------------------------------------买入信号
            first=universe{pair,Date+1}(1,1);
            second=universe{pair,Date+1}(1,2);

            if length(find(storage(:,Date+1)~=first))==storageRoom&&length(find(storage_Loan(:,Date+1)~=first))==storageRoom %买的股票没有持仓
                if length(find(storage_Loan(:,Date+1)~=second))==storageRoom&&length(find(storage(:,Date+1)~=second))==storageRoom %融的股票没有持仓
                    if length(find(storage(:,Date+1)==0))>0%如果舱内还有股票         
                            STOPprice=round(CLOSE(first,Date).*1.1.*100)./100;
                            STOPDprice=round(CLOSE(first,Date).*0.9.*100)./100;
                            STOPLoanprice=round(CLOSE(second,Date).*1.1.*100)./100;
                            STOPLoanDprice=round(CLOSE(second,Date).*0.9.*100)./100;
                            if OPEN(first,Date+1)<STOPprice&&OPEN(first,Date+1)>STOPDprice&&OPEN(second,Date+1)<STOPLoanprice&&OPEN(second,Date+1)>STOPLoanDprice%判断是否涨停
                                if STIUATION(first,Date+1)==1&&STIUATION(second,Date+1)==1%判断该对股票是否可以进行交易,若其中有任意一个不能交易,则全部不能交易
                                    
                                   CLOSEseries=[mean(CLOSE(first,1:Date)),mean(CLOSE(second,1:Date))];
                                   pos_bigger=find(CLOSEseries==max(CLOSEseries));
                                   pos_smaller=find(CLOSEseries==min(CLOSEseries));

                                   bigger=universe{pair,Date+1}(1,pos_bigger);
                                   smaller=universe{pair,Date+1}(1,pos_smaller);

                                   Diff=CLOSE(bigger,Date-histwindow:Date)-CLOSE(smaller,Date-histwindow:Date);
                                   lemda_positive=mean(Diff)+confidence_coeff.*std(Diff);
                                   lemda_negative=mean(Diff)-confidence_coeff.*std(Diff);
                                   if CLOSE(bigger,Date)-CLOSE(smaller,Date)>lemda_positive
                                       %卖空大的,做多小的
                                       each_lamda(smaller,Date+1)=mean(Diff);%+std(Diff);
            %-----------------------------------------------------------------------------------------------做多小的
                                        volume(smaller,Date+1)=cash(1,Date+1)./(length(find(storage(:,Date+1)==0)).*OPEN(smaller,Date+1)); 
            %-----------------------------------------------------------------------------------------------必须整手买 
                                        volume(smaller,Date+1)=HSLsec_Advanced_Limit_test_round(volume(smaller,Date+1),100);
            %-----------------------------------------------------------------------------------------------买的时候必须考虑资金余额
                                        [volume(smaller,Date+1),buy_commision(smaller,Date+1)]=HSLsec_Advanced_Limit_account_limit(cash(1,Date+1),volume(smaller,Date+1),OPEN(smaller,Date+1),commision_rate);
            %----------------------------------------------------------------------------------------------------------------------------------------------------------------- 
                                        tradeValue=volume(smaller,Date+1).*OPEN(smaller,Date+1);
                                        cash(1,Date+1)=cash(1,Date+1)-tradeValue-buy_commision(smaller,Date+1);
                                        if volume(smaller,Date+1)~=0
                                            buy(smaller,Date+1)=OPEN(smaller,Date+1);
                                            b=find(storage(:,Date+1)==0, 1 ,'first');
                                            storage(b,Date+1)=smaller;
                                            storage_name(b,Date+1)=secName(smaller,1);
                                            buy_record(b,Date+1)=secName(smaller,1);
                                            Condition(smaller,Date+1)=1;
                                            Condition(bigger,Date+1)=1;
                                        end 
            %---------------------------------------------------------------------------------做空大的
                                        Loan_volume(bigger,Date+1)=tradeValue./OPEN(bigger,Date+1);
                                        Loan_volume(bigger,Date+1)=HSLsec_Advanced_Limit_test_round(Loan_volume(bigger,Date+1),100);
                                        
                            %            Loan_volume(bigger,Date+1)=volume(smaller,Date+1);
                                        if Loan_volume(bigger,Date+1)~=0
                                            buyLoan(bigger,Date+1)=OPEN(bigger,Date+1);
                                            secLoanValue(bigger,Date+1)=OPEN(bigger,Date+1).*Loan_volume(bigger,Date+1);
                                            b=find(storage_Loan(:,Date+1)==0, 1 ,'first');
                                            storage_Loan(b,Date+1)=bigger;
                                            storage_Loan_name(b,Date+1)=secName(bigger,1);
                                            buyLoan_record(b,Date+1)=secName(bigger,1);
                                        end
                                   elseif CLOSE(bigger,Date)-CLOSE(smaller,Date)<lemda_negative
                                       %做多大的,做空小的
                                       each_lamda(bigger,Date+1)=mean(Diff);%-std(Diff);
            %-------------------------------------------------------------------------------------------------------------------------------------------做多大的
                                        volume(bigger,Date+1)=cash(1,Date+1)./(length(find(storage(:,Date+1)==0)).*OPEN(bigger,Date+1)); 
            %-----------------------------------------------------------------------------------------------------------------------------------------必须整手买 
                                        volume(bigger,Date+1)=HSLsec_Advanced_Limit_test_round(volume(bigger,Date+1),100);
            %------------------------------------------------------------------------------------------------------------------------------------------买的时候必须考虑资金余额
                                        [volume(bigger,Date+1),buy_commision(bigger,Date+1)]=HSLsec_Advanced_Limit_account_limit(cash(1,Date+1),volume(bigger,Date+1),OPEN(bigger,Date+1),commision_rate);
            %-----------------------------------------------------------------------------------------------------------------------------------------------------------------
                                        tradeValue=volume(bigger,Date+1).*OPEN(bigger,Date+1);
                                        cash(1,Date+1)=cash(1,Date+1)-tradeValue-buy_commision(bigger,Date+1);
                                        if volume(bigger,Date+1)~=0
                                            buy(bigger,Date+1)=OPEN(bigger,Date+1);
                                            b=find(storage(:,Date+1)==0, 1 );
                                            storage(b,Date+1)=bigger;
                                            storage_name(b,Date+1)=secName(bigger,1);
                                            buy_record(b,Date+1)=secName(bigger,1);
                                            Condition(smaller,Date+1)=2;
                                            Condition(bigger,Date+1)=2;
                                        end 
            %--------------------------------------------------------------------------------------------------------------------------------做空小的
                                        Loan_volume(smaller,Date+1)=tradeValue./OPEN(smaller,Date+1);
                                        Loan_volume(smaller,Date+1)=HSLsec_Advanced_Limit_test_round(Loan_volume(smaller,Date+1),100);
                                        if Loan_volume(smaller,Date+1)~=0
                                            buyLoan(smaller,Date+1)=OPEN(smaller,Date+1);
                   %                        
                                            secLoanValue(smaller,Date+1)=OPEN(smaller,Date+1).*Loan_volume(smaller,Date+1);
                                            b=find(storage_Loan(:,Date+1)==0, 1,'first' );
                                            storage_Loan(b,Date+1)=smaller;
                                            storage_Loan_name(b,Date+1)=secName(smaller,1);
                                            buyLoan_record(b,Date+1)=secName(smaller,1);
                                        end 
                                   end
                                end
                            end

                    else
                        break;
                    end
                else
                    continue;
                end
            end
        end
    end
    %--------------------------------------------每日收益

    %--------------------------------------------计算每一日资产价格 

        for i=1:length(storage(:,Date+1))
            if storage(i,Date+1)~=0

                capital(1,Date+1)=capital(1,Date+1)+volume(storage(i,Date+1),Date+1).*CLOSE(storage(i,Date+1),Date+1);
            end
        end
        for i=1:length(storage_Loan(:,Date+1))
            if storage_Loan(i,Date+1)~=0
                buydate=find(buyLoan(storage_Loan(i,Date+1),1:Date+1)~=0, 1, 'last' );
                temp=Loan_volume(storage_Loan(i,Date+1),buydate).*(OPEN(storage_Loan(i,Date+1),buydate)-CLOSE(storage_Loan(i,Date+1),Date+1));
                Loan_capital(1,Date+1)=Loan_capital(1,Date+1)+temp;
            end
        end
  
    
%--------------------------------------------计算完毕
end

accountValue=cash+capital+Loan_capital;
account_rt=(accountValue-cash(1,1))./cash(1,1);
[a,b]=find(perreturn_rate~=0);
pertrade=[];
for i=1:length(a)
    pertrade=[pertrade,perreturn_rate(a(i),b(i))];
end
A_result_perDay_rt=diff(accountValue(1,Observe+1:end))./accountValue(1,Observe+1:end-1);
A_result_Annual_sharp=(mean(A_result_perDay_rt)./std(A_result_perDay_rt)).*16;
%---------------------------------------------表格加工
win=length(find(pertrade>0))./length(pertrade);
maxday=find(account_rt==max(account_rt),1);
[bloc,floc,maxDrawDown]=maxdrawdown_maker(accountValue(Observe:end));%(max(accountValue)-min(accountValue(maxday:end)))./max(accountValue);
AnnualYeild=account_rt(length(account_rt))./length(tradeDate(Observe:end)).*250;
[a,b]=size(buy(:,Observe:end));
A_result_buy=cell(a+1,b+1);
A_result_buy(2:a+1,2:b+1)=num2cell(buy(:,Observe:end));
A_result_buy(1,2:b+1)=tradeDate(Observe:end);
A_result_buy(2:a+1,1)=secName;

A_result_sale=cell(a+1,b+1);
A_result_sale(2:a+1,2:b+1)=num2cell(sale(:,Observe:end));
A_result_sale(1,2:b+1)=tradeDate(Observe:end);
A_result_sale(2:a+1,1)=secName;

A_result_buy_commision=cell(a+1,b+1);
A_result_buy_commision(2:a+1,2:b+1)=num2cell(buy_commision(:,Observe:end));
A_result_buy_commision(1,2:b+1)=tradeDate(Observe:end);
A_result_buy_commision(2:a+1,1)=secName;
total_buyCom=sum(sum(sparse(buy_commision)));

A_result_sale_commision=cell(a+1,b+1);
A_result_sale_commision(2:a+1,2:b+1)=num2cell(sale_commision(:,Observe:end));
A_result_sale_commision(1,2:b+1)=tradeDate(Observe:end);
A_result_sale_commision(2:a+1,1)=secName;
total_saleCom=sum(sum(sparse(sale_commision)));

total_commision=total_saleCom+total_buyCom;

A_result_stamptax=cell(a+1,b+1);
A_result_stamptax(2:a+1,2:b+1)=num2cell(stamptax(:,Observe:end));
A_result_stamptax(1,2:b+1)=tradeDate(Observe:end);
A_result_stamptax(2:a+1,1)=secName;
total_stp=sum(sum(sparse(stamptax)));

total_extraspend=total_stp+total_commision;

A_result_volume=cell(a+1,b+1);
A_result_volume(2:a+1,2:b+1)=num2cell(volume(:,Observe:end));
A_result_volume(1,2:b+1)=tradeDate(Observe:end);
A_result_volume(2:a+1,1)=secName;

[c,d]=size(storage);
A_result_storage=cell(c+1,d);
A_result_storage(1,:)=tradeDate;
A_result_storage(2:c+1,:)=storage_name;
A_result_storage=A_result_storage(:,Observe:end);
A_result_buy_record=cell(c+1,d);
A_result_buy_record(1,:)=tradeDate;
A_result_buy_record(2:c+1,:)=buy_record;
A_result_buy_record=A_result_buy_record(:,Observe:end);
A_result_sale_record=cell(c+1,d);
A_result_sale_record(1,:)=tradeDate;
A_result_sale_record(2:c+1,:)=sale_record;
A_result_sale_record=A_result_sale_record(:,Observe:end);


[e,f]=size(account_rt(Observe:end));
A_result_accountRt=cell(e+1,f);
A_result_accountRt(1,:)=tradeDate(Observe:end);
A_result_accountRt(2,:)=num2cell(account_rt(Observe:end));
A_result_accountValue=cell(e+1,f);
A_result_accountValue(1,:)=tradeDate(Observe:end);
A_result_accountValue(2,:)=num2cell(accountValue(Observe:end));

A_result_dayreturn=cell(e+1,f);
A_result_dayreturn(1,:)=tradeDate(Observe:end);
A_result_dayreturn(2,:)=num2cell(dayreturn(Observe:end));

A_result_cash=cell(e+1,f);
A_result_cash(1,:)=tradeDate(Observe:end);
A_result_cash(2,:)=num2cell(cash(Observe:end));
A_result_capital=cell(e+1,f);
A_result_capital(1,:)=tradeDate(Observe:end);
A_result_capital(2,:)=num2cell(capital(Observe:end));

[g,h]=size(CLOSE);
A_result_CLOSE=cell(g+1,h+1);
A_result_CLOSE(2:g+1,2:h+1)=num2cell(CLOSE);
A_result_CLOSE(1,2:h+1)=tradeDate(1:end);
A_result_CLOSE(2:g+1,1)=secName;

[j,k]=size(OPEN);
A_result_OPEN=cell(j+1,k+1);
A_result_OPEN(2:j+1,2:k+1)=num2cell(OPEN);
A_result_OPEN(1,2:k+1)=tradeDate;
A_result_OPEN(2:j+1,1)=secName;
A_result_STIUATION=cell(j+1,k+1);
A_result_STIUATION(2:j+1,2:k+1)=num2cell(STIUATION);
A_result_STIUATION(1,2:k+1)=tradeDate;
A_result_STIUATION(2:j+1,1)=secName;


%----------------------------------------------表格加工结束

%----------------------------------------------可视化部分构建
figure(1)
subplot(2,1,1)
hold on 
temp=account_rt(Observe:end);
plot(temp)
plot(benchmark_rt)
plot(bloc:floc,temp(bloc:floc),'r','LineWidth',4)
hold off
title('Strategy Cumulative Return')
xlabel('time')
ylabel('The Rate of Return')
legend('The Rate of Return of Strategy','The Rate of Return of Index','The Time Slot that the MaxDrawback happened')
subplot(2,1,2)
hist(pertrade,100);
[f,xout]=hist(pertrade,100);
hist_high=linspace(max(f).*(1/5),max(f).*(4/5),6);
mean_per_trade=mean(pertrade);
std_trade=std(pertrade);
title('The Return of Every Transaction') 
xlabel('The Rate of Return of Every Transaction')
ylabel('Frequency')
text(xout(end-10),hist_high(6),sprintf('Annualized Rate of Return%s',strcat(num2str(AnnualYeild.*100),'%')))
text(xout(end-10),hist_high(5),sprintf('Mean of The Rate of Raturn%s',strcat(num2str(mean_per_trade.*100),'%') ))
text(xout(end-10),hist_high(4),sprintf('Variance of The Rate of Return%d',std_trade ))
text(xout(end-10),hist_high(3),sprintf('The Rate of Win%s',strcat(num2str(win.*100),'%') ))
text(xout(end-10),hist_high(2),sprintf('Max Drawdown%s',strcat(num2str(maxDrawDown.*100),'%')))
text(xout(end-10),hist_high(1),sprintf('Sharp Ratio%s',A_result_Annual_sharp))
%----------------------------------------------可视化部分结束
